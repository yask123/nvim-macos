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


def resonance(freq, tau, L, drop=0.0, drop_tau=0.004):
    """A damped sine: how a keycap, plate or case rings when struck."""
    tone = osc("sine", lambda t: freq * (1 + drop * math.exp(-t / drop_tau)), L)
    return mul(tone, env_exp(L, a=0.0004, tau=tau))


def room(x, taps=((0.007, 0.16), (0.013, 0.10), (0.021, 0.06), (0.034, 0.03))):
    """A few soft early reflections: a small wooden desk, not a hall."""
    wet = lowpass(x, 3200)
    items = [(0.0, x, 1.0)] + [(d, wet, g) for d, g in taps]
    return place(len(x) + n(0.04), items)


def warm(x, drive=1.6):
    """Gentle tape-style saturation: rounds the peaks, adds body."""
    t = math.tanh(drive)
    return [math.tanh(drive * v) / t for v in x]


def keystroke(seed, body=110, tok=1350, weight=1.0, release=True, dur=0.13):
    """
    A creamy mechanical key: three layers struck together, then released.
      tok     the keycap: a short hollow plastic ring (two partials) plus a
              whisper of band-passed noise for the contact
      body    bottom-out: a low damped thud with a small pitch drop, and the
              case answering an octave-and-a-bit above it
      release the upstroke ~50 ms later: a quieter, higher tok
    Then a little room and warmth. `weight` darkens and deepens (space, enter).
    """
    r = random.Random(seed)
    L = n(dur)
    tokf = tok * r.uniform(0.92, 1.08) / (0.85 + 0.15 * weight)
    click = mul(bandpass(noise(L, seed), 900, 4200), env_exp(L, a=0.0002, tau=0.0014))
    keycap = mix((resonance(tokf, 0.0055, L), 1.0), (resonance(tokf * 2.27, 0.0028, L), 0.35))
    bodyf = body * r.uniform(0.94, 1.06)
    thud = mix(
        (resonance(bodyf, 0.018 * weight, L, drop=0.3), 1.0),
        (resonance(bodyf * 2.6, 0.009, L), 0.28),
    )
    items = [(0.0, click, 0.2), (0.0, keycap, 0.55), (0.0015, thud, 0.8)]
    if release:
        up = mix((resonance(tokf * 1.12, 0.004, L), 1.0), (resonance(tokf * 2.5, 0.002, L), 0.3))
        items.append((r.uniform(0.042, 0.062), up, 0.16))
    x = place(L, items)
    x = lowpass(x, 7000 / (0.8 + 0.2 * weight))
    return room(warm(x))


# Game cues: soft chiptune voices, all in D major pentatonic (D E F# A B) so
# every sound agrees with every other one, and with the keys.
def soft_pulse(freq, dur, duty=0.25, lp=2600, tau=None, vib=0.0, sub=0.35):
    """A square wave with the fizz filtered off, a sine an octave down for
    roundness, and a short echo: 8-bit in spirit, gentle on the ears."""
    L = n(dur)
    fn = (lambda t: freq * (1 + vib * math.sin(2 * math.pi * 5.5 * t))) if vib else (lambda t: freq)
    x = lowpass(osc("square", fn, L, duty=duty), lp)
    low = osc("sine", lambda t: freq / 2, L)
    env = env_exp(L, a=0.003, tau=tau or dur / 2.5)
    return mul(mix((x, 1.0), (low, sub)), env)


def jingle(notes, echo=0.24):
    """notes: (start, name, dur[, kind]) -> one phrase with a soft 95 ms echo."""
    end = max(start + dur for start, _, dur, *_ in notes) + 0.3
    items = []
    for start, name, dur, *kind in notes:
        f = note(name)
        voice = soft_pulse(f, dur) if not kind else mul(osc("tri", lambda t: f, n(dur)), env_exp(n(dur), a=0.003, tau=dur / 2.5))
        items.append((start, voice, 1.0))
        items.append((start + 0.095, lowpass(voice, 1800), echo))
    return place(n(end), items)


# --------------------------------------------------------------------------- the pack
print(f"writing to {OUT}")

# typing: 8 variations (the daemon adds a little pitch/level/pan jitter too)
# (Tuned for laptop speakers too: the "thock" lives around 250-450 Hz, the
# keycap around 2 kHz; nothing relies on bass a MacBook can't play.)
for i in range(1, 9):
    r = random.Random(100 + i)
    write(f"key_{i}", keystroke(100 + i, body=r.uniform(300, 350), tok=r.uniform(1900, 2300)), -21)
# space: deeper and rounder, the long bar settling
for i in range(1, 4):
    write(f"space_{i}", keystroke(200 + i, body=220, tok=1500, weight=1.4, dur=0.16), -20)
# enter: the most satisfying one
write("enter", keystroke(301, body=200, tok=1350, weight=1.6, dur=0.18), -19)
# backspace: lighter and a little higher, like a small key
write("backspace", keystroke(401, body=380, tok=2600, weight=0.8, release=False, dur=0.1), -23)

# save: a coin-style pickup, a fourth up (A5 -> D6) with a gentle shimmer
write("save", place(n(0.55), [
    (0.0, soft_pulse(note("A5"), 0.06, tau=0.05), 0.8),
    (0.055, soft_pulse(note("D6"), 0.34, tau=0.14, vib=0.006), 1.0),
    (0.15, lowpass(soft_pulse(note("D6"), 0.34, tau=0.14), 1800), 0.22),
]), -21)

# run finished: a quick "stage clear" arpeggio up to the octave
write("run_ok", jingle([(0.0, "D5", 0.07), (0.06, "F#5", 0.07), (0.12, "A5", 0.07), (0.18, "D6", 0.34)]), -20)

# run failed: a soft two-note "bonk" down, triangle, no alarm
write("run_err", jingle([(0.0, "A4", 0.1, "tri"), (0.1, "E4", 0.26, "tri")], echo=0.12), -21)

# opening a project: a short power-up
write("start", jingle([(0.0, "D5", 0.06), (0.05, "A5", 0.06), (0.1, "D6", 0.06), (0.15, "F#6", 0.06), (0.2, "A6", 0.3)]), -20)

# yank (copy): a tiny sparkle
write("yank", jingle([(0.0, "B6", 0.05, "tri"), (0.045, "F#7", 0.12, "tri")], echo=0.15), -24)

# (off by default, kept so the pack is complete)
write("paste", blip(note("A5"), note("D5"), 0.08, kind="sine"), -20)
write("undo", blip(1200, 600, 0.08, kind="tri"), -23)
write("redo", blip(600, 1200, 0.08, kind="tri"), -23)
write("mode_insert", blip(note("D5"), note("A5"), 0.06), -23)
write("mode_normal", blip(note("A5"), note("D5"), 0.06), -24)
write("mode_visual", blip(note("F#5"), note("B5"), 0.05), -24)
write("quit", jingle([(0.0, "A5", 0.07, "tri"), (0.07, "F#5", 0.07, "tri"), (0.14, "D5", 0.25, "tri")], echo=0.12), -22)
write("notify", jingle([(0.0, "E6", 0.2, "tri")], echo=0.1), -26)
print("done")
