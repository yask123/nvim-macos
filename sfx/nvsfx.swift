// nvsfx.swift - a tiny persistent sound-effect daemon for Neovim on macOS.
//
// Build:  swiftc -O -swift-version 5 nvsfx.swift -o nvsfx
// Run:    nvsfx --dir ./sounds [--volume 0.35] [--buffer 256] [--idle-suspend 30] [--bench]
//
// Protocol: one command per line on stdin (UTF-8). Unknown names are ignored silently.
//   <name>                      play sample <name> (or a random variant <name>_1.. <name>_N)
//   play <name> [gain] [semis]  same, with explicit gain (0..2) and pitch offset in semitones
//   vol <0..1>                  master volume
//   mute | unmute | toggle      mute state
//   ping <token>                replies "pong <token>" on stdout (liveness / RTT check)
//   list                        prints loaded sample names on stdout
//   quit                        exit (also exits on stdin EOF, i.e. when Neovim dies)
//
// Design: all samples are decoded once into float arrays. A single AVAudioSourceNode renders a
// fixed pool of voices (linear-interpolation resampling gives cheap per-hit pitch jitter), so a
// trigger costs one lock-protected ring-buffer push; nothing is allocated on the audio thread.

import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import os

// ------------------------------------------------------------------ options
var dir = FileManager.default.currentDirectoryPath + "/sounds"
var masterVolume: Float = 0.35
var bufferFrames: UInt32 = 256
var idleSuspend: Double = 0  // seconds, 0 = never suspend
var bench = false
do {
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let a = args.next() {
        switch a {
        case "--dir": dir = args.next() ?? dir
        case "--volume": masterVolume = Float(args.next() ?? "") ?? masterVolume
        case "--buffer": bufferFrames = UInt32(args.next() ?? "") ?? bufferFrames
        case "--idle-suspend": idleSuspend = Double(args.next() ?? "") ?? idleSuspend
        case "--bench": bench = true
        default: FileHandle.standardError.write("nvsfx: unknown option \(a)\n".data(using: .utf8)!)
        }
    }
}

func log(_ s: String) { FileHandle.standardError.write(("nvsfx: " + s + "\n").data(using: .utf8)!) }
setvbuf(stdout, nil, _IOLBF, 0)

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
@inline(__always) func hostToNs(_ t: UInt64) -> Double { Double(t) * Double(timebase.numer) / Double(timebase.denom) }

// ------------------------------------------------------------------ samples
struct Sample {
    let data: UnsafeMutablePointer<Float>
    let count: Int
    let rate: Double
}
var samples: [Sample] = []
var groups: [String: [Int32]] = [:]  // "key" -> [idx of key_1..key_4]; "save" -> [idx]

func loadSamples() {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: dir) else { log("cannot read \(dir)"); exit(2) }
    for f in files.sorted() where f.hasSuffix(".wav") || f.hasSuffix(".aif") || f.hasSuffix(".caf") {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(f)
        guard let file = try? AVAudioFile(forReading: url),
              let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate, channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))
        else { log("skip \(f)"); continue }
        // AVAudioFile converts to the processing format; ask for mono float by reading via a converter if needed
        do {
            if file.processingFormat.channelCount == 1 {
                try file.read(into: buf)
            } else {
                let tmp = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: tmp)
                let conv = AVAudioConverter(from: file.processingFormat, to: fmt)!
                try conv.convert(to: buf, from: tmp)
            }
        } catch { log("read failed \(f): \(error)"); continue }
        let n = Int(buf.frameLength)
        let p = UnsafeMutablePointer<Float>.allocate(capacity: n + 2)
        p.update(from: buf.floatChannelData![0], count: n)
        p[n] = 0; p[n + 1] = 0  // guard samples for interpolation
        samples.append(Sample(data: p, count: n, rate: file.fileFormat.sampleRate))
        var base = (f as NSString).deletingPathExtension
        // strip a trailing _<digits> to form variant groups
        if let r = base.range(of: "_[0-9]+$", options: .regularExpression) { base.removeSubrange(r) }
        groups[base, default: []].append(Int32(samples.count - 1))
    }
    if samples.isEmpty { log("no samples in \(dir)"); exit(2) }
}

// Per-group humanization: (pitch jitter semitones, gain jitter dB, pan jitter, min retrigger ms)
func variation(for group: String) -> (Float, Float, Float, Double) {
    switch group {
    case "key", "space", "backspace", "enter": return (0.5, 2.0, 0.15, 18)
    case let g where g.hasPrefix("mode_"): return (0.15, 1.0, 0.0, 40)
    default: return (0.0, 0.0, 0.0, 60)
    }
}

// ------------------------------------------------------------------ lock-free-ish trigger ring (producer: stdin thread, consumer: audio thread)
struct Trigger {
    var sample: Int32 = 0
    var step: Double = 1
    var gainL: Float = 0
    var gainR: Float = 0
    var readHost: UInt64 = 0
    var benchId: Int32 = -1
}
let ringCap = 64
let ring = UnsafeMutablePointer<Trigger>.allocate(capacity: ringCap); ring.initialize(repeating: Trigger(), count: ringCap)
var ringHead = 0, ringTail = 0  // guarded by lock
let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1); lock.initialize(to: os_unfair_lock())

// bench results (audio thread -> reporter thread), same lock discipline
struct BenchResult { var id: Int32; var toCallbackNs: Double; var toOutputNs: Double }
let benchCap = 256
let benchRing = UnsafeMutablePointer<BenchResult>.allocate(capacity: benchCap)
var benchHead = 0, benchTail = 0

// ------------------------------------------------------------------ voices (owned by the audio thread only)
struct Voice {
    var active = false
    var sample: Int32 = 0
    var pos: Double = 0
    var step: Double = 1
    var gainL: Float = 0
    var gainR: Float = 0
    var age: UInt64 = 0
}
let maxVoices = 24
let voices = UnsafeMutablePointer<Voice>.allocate(capacity: maxVoices); voices.initialize(repeating: Voice(), count: maxVoices)
var voiceClock: UInt64 = 0
var activeVoices = 0  // written by audio thread, read (racy but harmless) by idle timer
var muted = false
var outRate: Double = 48000

// ------------------------------------------------------------------ engine
let engine = AVAudioEngine()
var sourceNode: AVAudioSourceNode!

func makeSourceNode(rate: Double) -> AVAudioSourceNode {
    let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    return AVAudioSourceNode(format: fmt) { isSilence, timestamp, frameCount, abl -> OSStatus in
        let nowHost = mach_absolute_time()
        // 1. drain pending triggers (never block the audio thread)
        if os_unfair_lock_trylock(lock) {
            while ringTail != ringHead {
                let t = ring[ringTail]; ringTail = (ringTail + 1) % ringCap
                // pick a free voice, else steal the oldest
                var slot = 0, oldest = UInt64.max
                for i in 0..<maxVoices {
                    if !voices[i].active { slot = i; break }
                    if voices[i].age < oldest { oldest = voices[i].age; slot = i }
                }
                voiceClock &+= 1
                voices[slot] = Voice(active: true, sample: t.sample, pos: 0, step: t.step, gainL: t.gainL, gainR: t.gainR, age: voiceClock)
                if t.benchId >= 0 {
                    let outHost = timestamp.pointee.mHostTime
                    benchRing[benchHead] = BenchResult(id: t.benchId,
                                                       toCallbackNs: hostToNs(nowHost) - hostToNs(t.readHost),
                                                       toOutputNs: hostToNs(outHost) - hostToNs(t.readHost))
                    benchHead = (benchHead + 1) % benchCap
                }
            }
            os_unfair_lock_unlock(lock)
        }
        // 2. mix
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        let L = buffers[0].mData!.assumingMemoryBound(to: Float.self)
        let R = buffers[1].mData!.assumingMemoryBound(to: Float.self)
        let n = Int(frameCount)
        for i in 0..<n { L[i] = 0; R[i] = 0 }
        var live = 0
        for v in 0..<maxVoices where voices[v].active {
            let s = samples[Int(voices[v].sample)]
            var pos = voices[v].pos
            let step = voices[v].step, gl = voices[v].gainL, gr = voices[v].gainR
            var i = 0
            while i < n {
                let ip = Int(pos)
                if ip >= s.count { voices[v].active = false; break }
                let frac = Float(pos - Double(ip))
                let x = s.data[ip] + (s.data[ip + 1] - s.data[ip]) * frac
                L[i] += x * gl; R[i] += x * gr
                pos += step; i += 1
            }
            voices[v].pos = pos
            if voices[v].active { live += 1 }
        }
        activeVoices = live
        // 3. master gain + gentle soft clip
        let g: Float = muted ? 0 : masterVolume
        var any = false
        for i in 0..<n {
            var l = L[i] * g, r = R[i] * g
            if abs(l) > 0.9 { l = l > 0 ? 0.9 + tanhf(l - 0.9) * 0.1 : -0.9 + tanhf(l + 0.9) * 0.1 }
            if abs(r) > 0.9 { r = r > 0 ? 0.9 + tanhf(r - 0.9) * 0.1 : -0.9 + tanhf(r + 0.9) * 0.1 }
            L[i] = l; R[i] = r
            if l != 0 || r != 0 { any = true }
        }
        isSilence.pointee = ObjCBool(!any)
        return noErr
    }
}

func setIOBufferSize(_ frames: UInt32) {
    guard frames > 0, let au = engine.outputNode.audioUnit else { return }
    var f = frames
    let st = AudioUnitSetProperty(au, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &f, UInt32(MemoryLayout<UInt32>.size))
    if st != noErr { log("could not set buffer size (\(st))") }
}

func currentIOBufferSize() -> UInt32 {
    guard let au = engine.outputNode.audioUnit else { return 0 }
    var f: UInt32 = 0
    var sz = UInt32(MemoryLayout<UInt32>.size)
    AudioUnitGetProperty(au, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &f, &sz)
    return f
}

let control = DispatchQueue(label: "nvsfx.control")
var idleTimer: DispatchSourceTimer?
var lastPlayNs: Double = 0

func buildAndStart() {
    if sourceNode != nil { engine.detach(sourceNode) }
    outRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    if outRate <= 0 { outRate = 48000 }
    sourceNode = makeSourceNode(rate: outRate)
    engine.attach(sourceNode)
    engine.connect(sourceNode, to: engine.mainMixerNode, format: sourceNode.outputFormat(forBus: 0))
    setIOBufferSize(bufferFrames)
    engine.prepare()
    do { try engine.start() } catch { log("engine start failed: \(error)") }
    let pl = engine.outputNode.presentationLatency
    log(String(format: "ready: %d samples, out %.0f Hz, io buffer %u frames (%.1f ms), presentationLatency %.1f ms",
               samples.count, outRate, currentIOBufferSize(), Double(currentIOBufferSize()) / outRate * 1000, pl * 1000))
}

// Output device changes (AirPods connect, display audio, etc.) stop the engine; rebuild on change.
NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
    control.async { log("audio configuration changed, restarting"); buildAndStart() }
}

// ------------------------------------------------------------------ command handling
var lastTrigger: [String: Double] = [:]

func enqueue(group: String, gain: Float?, semis: Float?, readHost: UInt64, benchId: Int32) {
    guard !muted, let idxs = groups[group], !idxs.isEmpty else { return }
    let (pj, gj, panj, minMs) = variation(for: group)
    let nowNs = hostToNs(readHost)
    if let last = lastTrigger[group], (nowNs - last) < minMs * 1e6, benchId < 0 { return }  // backstop rate limit
    lastTrigger[group] = nowNs
    let idx = idxs[Int.random(in: 0..<idxs.count)]
    let s = samples[Int(idx)]
    let semi = (semis ?? 0) + (pj > 0 ? Float.random(in: -pj...pj) : 0)
    let db = gj > 0 ? Float.random(in: -gj...gj) : 0
    let g = (gain ?? 1) * powf(10, db / 20)
    let pan = panj > 0 ? Float.random(in: -panj...panj) : 0  // -1..1
    let a = (pan + 1) * Float.pi / 4  // equal-power
    var t = Trigger()
    t.sample = idx
    t.step = (s.rate / outRate) * Double(powf(2, semi / 12))
    t.gainL = g * cosf(a) * Float(2).squareRoot()  // centre pan -> unity gain on both sides
    t.gainR = g * sinf(a) * Float(2).squareRoot()
    t.readHost = readHost
    t.benchId = benchId
    os_unfair_lock_lock(lock)
    let next = (ringHead + 1) % ringCap
    if next != ringTail { ring[ringHead] = t; ringHead = next }  // drop if full
    os_unfair_lock_unlock(lock)
    lastPlayNs = nowNs
    if !engine.isRunning {  // idle-suspended, or a failed start/device switch: retry
        control.sync {
            let t0 = mach_absolute_time()
            do { try engine.start() } catch { log("resume failed: \(error)") }
            if bench { print(String(format: "resume_ms %.2f", (hostToNs(mach_absolute_time()) - hostToNs(t0)) / 1e6)) }
        }
    }
}

func handle(_ line: Substring, readHost: UInt64) {
    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
    guard let cmd = parts.first else { return }
    switch cmd {
    case "play":
        guard parts.count >= 2 else { return }
        let gain = parts.count > 2 ? Float(parts[2]) : nil
        let semis = parts.count > 3 ? Float(parts[3]) : nil
        enqueue(group: String(parts[1]), gain: gain, semis: semis, readHost: readHost, benchId: -1)
    case "bplay":  // bench: bplay <id> <name>
        guard parts.count >= 3, let id = Int32(parts[1]) else { return }
        enqueue(group: String(parts[2]), gain: nil, semis: nil, readHost: readHost, benchId: id)
    case "vol": if parts.count > 1, let v = Float(parts[1]) { masterVolume = max(0, min(1, v)) }
    case "mute": muted = true
    case "unmute": muted = false
    case "toggle": muted.toggle()
    case "ping": print("pong " + (parts.count > 1 ? String(parts[1]) : ""))
    case "list": print(groups.keys.sorted().joined(separator: " "))
    case "quit": exit(0)
    default: enqueue(group: String(cmd), gain: nil, semis: nil, readHost: readHost, benchId: -1)
    }
}

// ------------------------------------------------------------------ main
loadSamples()
control.sync { buildAndStart() }

if bench {
    // reporter thread: moves results from the audio thread to stdout
    Thread.detachNewThread {
        while true {
            usleep(1000)
            var out: [BenchResult] = []
            os_unfair_lock_lock(lock)
            while benchTail != benchHead { out.append(benchRing[benchTail]); benchTail = (benchTail + 1) % benchCap }
            os_unfair_lock_unlock(lock)
            for r in out { print(String(format: "lat %d %.1f %.1f", r.id, r.toCallbackNs / 1000, r.toOutputNs / 1000)) }
        }
    }
}

if idleSuspend > 0 {
    let timer = DispatchSource.makeTimerSource(queue: control)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler {
        os_unfair_lock_lock(lock)
        let pending = ringHead != ringTail
        os_unfair_lock_unlock(lock)
        if engine.isRunning && !pending && activeVoices == 0 && hostToNs(mach_absolute_time()) - lastPlayNs > idleSuspend * 1e9 {
            engine.pause()
            if bench { print("suspended") }
        }
    }
    timer.resume()
    idleTimer = timer
}

// stdin reader on its own thread; EOF (Neovim exited or crashed) -> exit after tails ring out
Thread.detachNewThread {
    while let line = readLine(strippingNewline: true) {
        handle(Substring(line), readHost: mach_absolute_time())
    }
    // let tails (e.g. a quit jingle sent right before Neovim exited) ring out, max 1.5 s
    usleep(60_000)
    var waited = 0
    while waited < 1_500 && engine.isRunning && (activeVoices > 0 || ringHead != ringTail) { usleep(20_000); waited += 20 }
    exit(0)
}
print("ready")
RunLoop.main.run()
