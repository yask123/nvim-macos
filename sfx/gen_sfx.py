#!/usr/bin/env python3
"""
gen_sfx.py - procedurally synthesize a small, tasteful "retro game" SFX pack
using only the Python standard library (wave, math, struct, random).

Output: 48 kHz, mono, 16-bit PCM WAV files in ./sounds (or argv[1]).
Naming: <event>.wav or <event>_<n>.wav (variants; the daemon picks one at random).

Design rules that keep it "relaxed, not annoying":
  * square/pulse waves are always softened with a one-pole low-pass (no fizzy harmonics)
  * every sound has a >= 2 ms fade-in and an exponential tail (no clicks)
  * typing ticks peak at -20 dBFS, UI cues at -12..-14 dBFS, jingles at -12 dBFS
  * everything is short: ticks 35-70 ms, cues 60-250 ms, the start jingle ~0.9 s
"""
import math
import os
import random
import struct
import sys
import wave

SR = 48000
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "sounds")
os.makedirs(OUT, exist_ok=True)
for old in os.listdir(OUT):  # removed or renamed variants must not linger
    if old.endswith(".wav"):
        os.remove(os.path.join(OUT, old))
random.seed(7)  # deterministic pack


# --------------------------------------------------------------------------- primitives
def n(sec):
    return max(1, int(sec * SR))


def note(name):
    """'A4' -> Hz, supports sharps like 'C#5'."""
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


def osc(kind, freq_fn, length, duty=0.5, phase0=0.0):
    """Band-naive oscillator. freq_fn(t_sec) -> Hz (allows glides/vibrato)."""
    out = [0.0] * length
    ph = phase0
    for i in range(length):
        f = freq_fn(i / SR)
        ph = (ph + f / SR) % 1.0
        if kind == "sine":
            v = math.sin(2 * math.pi * ph)
        elif kind == "tri":
            v = 4 * abs(ph - 0.5) - 1
        elif kind == "square":
            v = 1.0 if ph < duty else -1.0
        elif kind == "saw":
            v = 2 * ph - 1
        else:
            raise ValueError(kind)
        out[i] = v
    return out


def noise(length, seed=None):
    r = random.Random(seed)
    return [r.uniform(-1, 1) for _ in range(length)]


def lowpass(x, cutoff):
    """One-pole low-pass. cutoff may be a float or fn(t)."""
    y, prev = [0.0] * len(x), 0.0
    for i, v in enumerate(x):
        fc = cutoff(i / SR) if callable(cutoff) else cutoff
        a = 1 - math.exp(-2 * math.pi * fc / SR)
        prev += a * (v - prev)
        y[i] = prev
    return y


def highpass(x, cutoff):
    lp = lowpass(x, cutoff)
    return [a - b for a, b in zip(x, lp)]


def bandpass(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def env_adsr(length, a=0.002, d=0.05, s=0.0, r=0.03, curve=4.0):
    """Attack (linear) -> exponential decay to sustain -> exponential release at end."""
    e = [0.0] * length
    na, nd, nr = n(a), n(d), n(r)
    for i in range(length):
        if i < na:
            v = i / na
        elif i < na + nd:
            k = (i - na) / nd
            v = s + (1 - s) * math.exp(-curve * k)
        else:
            v = s
        tail = length - i
        if tail < nr:
            v *= (tail / nr) ** 2
        e[i] = v
    return e


def env_exp(length, a=0.001, tau=0.03):
    e = [0.0] * length
    na = n(a)
    for i in range(length):
        v = (i / na) if i < na else math.exp(-(i - na) / (tau * SR))
        e[i] = v
    # guaranteed zero at the end
    fade = min(n(0.004), length)
    for k in range(fade):
        e[length - 1 - k] *= k / fade
    return e


def mul(x, e):
    return [a * b for a, b in zip(x, e)]


def mix(*tracks):
    length = max(len(t) for t, _ in tracks)
    out = [0.0] * length
    for t, g in tracks:
        for i, v in enumerate(t):
            out[i] += g * v
    return out


def seq(parts, gap=0.0):
    out = []
    for p in parts:
        out += p + [0.0] * n(gap)
    return out


def place(dst_len, items):
    """items: list of (start_sec, samples, gain) -> overlap-add."""
    out = [0.0] * dst_len
    for start, x, g in items:
        s0 = n(start) if start > 0 else 0
        for i, v in enumerate(x):
            j = s0 + i
            if j < dst_len:
                out[j] += g * v
    return out


def normalize(x, peak_db):
    peak = max(1e-9, max(abs(v) for v in x))
    g = 10 ** (peak_db / 20) / peak
    return [v * g for v in x]


def finish(x):
    """DC-block (pulse waves carry DC) and force a 5 ms fade-out so nothing ever clicks."""
    x = highpass(x, 25)
    f = min(n(0.005), len(x))
    for k in range(f):
        x[len(x) - 1 - k] *= k / f
    return x


def write(name, x, peak_db):
    x = normalize(finish(x), peak_db)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in x))
    print(f"  {name + '.wav':<22} {len(x) / SR * 1000:6.0f} ms  peak {peak_db} dBFS")


# --------------------------------------------------------------------------- instruments
def chip_note(freq, dur, kind="square", duty=0.25, lp=3500, a=0.002, d=0.08, s=0.35, r=0.04, vib=0.0):
    L = n(dur)
    f = (lambda t: freq * (1 + vib * math.sin(2 * math.pi * 6 * t))) if vib else (lambda t: freq)
    x = osc(kind, f, L, duty=duty)
    if kind in ("square", "saw"):
        x = lowpass(x, lp)
    return mul(x, env_adsr(L, a=a, d=d, s=s, r=r))


def blip(f0, f1, dur, kind="tri", lp=4000):
    """Short pitch glide, exponential."""
    L = n(dur)
    x = osc(kind, lambda t: f0 * (f1 / f0) ** (t / dur), L, duty=0.5)
    if kind != "sine":
        x = lowpass(x, lp)
    return mul(x, env_exp(L, a=0.002, tau=dur / 3))


def thock(body_hz=180, body_tau=0.018, click_hz=(1800, 5200), click_gain=0.45, dur=0.06, seed=0, knock=0.0):
    """
    Soft mechanical key 'thock':
      - a very short band-passed noise transient (the keycap click)
      - a low, fast-decaying sine body with a small downward pitch drop (the 'thock')
      - optional 'knock' (second, lower resonance) for space/enter
    """
    L = n(dur)
    tr = bandpass(noise(L, seed), click_hz[0], click_hz[1])
    tr = mul(tr, env_exp(L, a=0.0003, tau=0.0025))
    body = osc("sine", lambda t: body_hz * (1 + 0.35 * math.exp(-t / 0.004)), L)
    body = mul(body, env_exp(L, a=0.0008, tau=body_tau))
    tracks = [(tr, click_gain), (body, 1.0)]
    if knock:
        kb = osc("sine", lambda t: body_hz * 0.62, L)
        tracks.append((mul(kb, env_exp(L, a=0.002, tau=body_tau * 1.6)), knock))
    # gentle overall low-pass so it sits under the music, not on top of it
    return lowpass(mix(*tracks), 6000)


# --------------------------------------------------------------------------- the pack
print(f"writing to {OUT}")

# typing ticks: 4 variants, the daemon adds +-0.5 semitone / +-2 dB jitter on top
for i, (hz, seed) in enumerate([(175, 1), (190, 2), (168, 3), (182, 4)], start=1):
    write(f"key_{i}", thock(body_hz=hz, seed=seed), -20)
# space/enter: deeper, a touch longer, with a second resonance
for i, (hz, seed) in enumerate([(128, 11), (136, 12)], start=1):
    write(f"space_{i}", thock(body_hz=hz, body_tau=0.024, dur=0.075, seed=seed, knock=0.35, click_gain=0.35), -19)
write("enter", thock(body_hz=118, body_tau=0.03, dur=0.09, seed=21, knock=0.5, click_gain=0.3), -17)
# backspace: lighter, higher, less body
write("backspace", thock(body_hz=240, body_tau=0.012, dur=0.045, seed=31, click_gain=0.6), -22)

# The "refined" cues: soft bell tones (sine fundamental + gentle, slightly
# inharmonic partials), quick attack, natural decay. Quiet by design.
def bell(freq, dur, tau=None):
    L = n(dur)
    tau = tau or dur / 3.5
    parts = [(1.0, 1.0), (2.0, 0.22), (3.01, 0.06), (4.2, 0.025)]
    x = [0.0] * L
    for ratio, amp in parts:
        tone = osc("sine", lambda t, r=ratio: freq * r, L)
        env = env_exp(L, a=0.003, tau=tau / ratio ** 0.5)
        for i in range(L):
            x[i] += amp * tone[i] * env[i]
    return x


# save: one soft bell (A5), like a quiet confirmation
write("save", bell(note("A5"), 0.42), -24)

# run succeeded: two bells rising a fifth (E5 -> B5)
write("run_ok", place(n(0.62), [(0.0, bell(note("E5"), 0.36), 0.9), (0.11, bell(note("B5"), 0.5), 1.0)]), -21)

# run failed: a single low, muted bell (A3), no alarm
write("run_err", lowpass(bell(note("A3"), 0.45, tau=0.09), 1400), -22)

# mode changes: soft triangle blips, up for insert, down for normal
write("mode_insert", blip(note("E5"), note("B5"), 0.07), -21)
write("mode_normal", blip(note("B5"), note("E5"), 0.07), -22)
write("mode_visual", blip(note("G5"), note("D6"), 0.06), -22)

# yank = sparkle pickup (two quick high tri notes), paste = soft 'plop'
write("yank", seq([chip_note(note("A6"), 0.04, kind="tri", d=0.03, s=0.5, r=0.01),
                   chip_note(note("E7"), 0.11, kind="tri", d=0.09, s=0.0, r=0.04)]), -19)
write("paste", blip(note("A5"), note("D5"), 0.08, kind="sine"), -18)

# undo = quick 'rewind' down-sweep, redo = up-sweep
write("undo", blip(1400, 520, 0.09, kind="square", lp=2200), -21)
write("redo", blip(520, 1400, 0.09, kind="square", lp=2200), -21)

# open project = start jingle (~0.9 s): pulse lead + triangle bass
lead_notes = [("G5", 0.09), ("C6", 0.09), ("E6", 0.09), ("G6", 0.12), ("E6", 0.09), ("G6", 0.36)]
t, items = 0.0, []
for nn, d in lead_notes:
    items.append((t, chip_note(note(nn), d + 0.02, duty=0.25, lp=3800, d=0.06, s=0.45, r=0.03, vib=0.004 if d > 0.3 else 0), 0.8))
    t += d
for start, nn, d in [(0.0, "C3", 0.36), (0.36, "G3", 0.20), (0.56, "C4", 0.40)]:
    items.append((start, chip_note(note(nn), d, kind="tri", d=0.15, s=0.5, r=0.06), 0.9))
write("start", place(n(t + 0.1), items), -12)

# quit = power-down (reverse-ish of start, short)
write("quit", seq([chip_note(note(x), 0.07, kind="tri", d=0.05, s=0.4, r=0.01) for x in ["G5", "E5", "C5"]] +
                  [chip_note(note("G4"), 0.18, kind="tri", d=0.15, s=0.0, r=0.06)]), -15)

# notification / diagnostic error: two-tone soft chime
write("notify", bell(note("E6"), 0.3), -26)
print("done")
