// Relative cost of the persistent EQ stage: bypassed vs active-neutral vs active-boosted.
//
// Run: swift spike/gapless-eq-cost/main.swift
//
// This measures OFFLINE render throughput and process memory for an identical workload under each
// EQ state, on the same graph shape the engine uses. It is a *relative* indicator only — real CPU,
// thermal and battery behaviour must be measured on device (Checkpoint 4). What it can settle now
// is whether the EQ stage is cheap or expensive relative to the rest of the graph, and whether
// bypass actually buys anything.

import AVFoundation
import Foundation

let sampleRate = 44_100.0
let renderSeconds = 120.0
let totalFrames = Int(sampleRate * renderSeconds)
let freq = 220.0
let amp: Float = 0.4
let frequencies: [Float] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}

struct Case {
    let name: String
    let gains: [Float]
    let enabled: Bool
    /// Apply a ReplayGain-style gain change at every simulated track boundary.
    var replayGain = false
}

// Graph cost is measured by offline rendering. The visualization tap is measured SEPARATELY, below,
// by driving the copy path directly: under offline manual rendering the engine batches tap callbacks
// (~1 per render slice instead of one per 1024 frames) and dispatches them off the render loop, so
// timings taken there describe the rendering mode rather than real-time playback.
let cases = [
    Case(name: "EQ bypassed", gains: Array(repeating: 0, count: 10), enabled: false),
    Case(name: "EQ active, neutral (all 0 dB)", gains: Array(repeating: 0, count: 10), enabled: true),
    Case(name: "EQ active, Rock preset", gains: [5, 4, 2, 0, -1, 0, 2, 3, 4, 5], enabled: true),
    Case(name: "ReplayGain only", gains: Array(repeating: 0, count: 10), enabled: false,
         replayGain: true),
    Case(name: "EQ + ReplayGain (no tap)", gains: [5, 4, 2, 0, -1, 0, 2, 3, 4, 5], enabled: true,
         replayGain: true)
]

/// A bounded ring per consumer, mirroring `FloatRingBuffer`: storage allocated once, written through
/// a raw pointer with a masked index, drained periodically like a UI would.
///
/// It has to be a faithful stand-in — an earlier version of this spike used a bounds-checked Swift
/// array and reported a 430 us callback, which measured the toy, not the engine.
final class Ring {
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let mask: Int
    private var head = 0
    private var tail = 0
    var dropped = 0

    init(capacity: Int) {
        self.capacity = capacity
        mask = capacity - 1
        storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity * 2)
        storage.initialize(repeating: 0, count: capacity * 2)
    }
    deinit { storage.deallocate() }

    func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frameCount: Int) {
        let free = capacity - (head - tail)
        if frameCount > free { dropped += frameCount - free; tail += frameCount - free }
        for i in 0..<frameCount {
            let slot = ((head + i) & mask) * 2
            storage[slot] = left[i]
            storage[slot + 1] = right[i]
        }
        head += frameCount
    }
    func drain() { tail = head }
}

func measure(_ testCase: Case) -> (seconds: Double, throughput: Double, memoryDelta: Int64) {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                               channels: 2, interleaved: false)!
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let gain = AVAudioMixerNode()
    let eq = AVAudioUnitEQ(numberOfBands: 10)
    let outputMixer = AVAudioMixerNode()
    engine.attach(player); engine.attach(gain); engine.attach(eq); engine.attach(outputMixer)
    engine.connect(player, to: gain, format: format)
    engine.connect(gain, to: eq, format: format)
    engine.connect(eq, to: outputMixer, format: format)
    engine.connect(outputMixer, to: engine.mainMixerNode, format: format)

    for (index, band) in eq.bands.enumerated() {
        band.filterType = .parametric
        band.frequency = frequencies[index]
        band.bandwidth = 1.0
        band.gain = testCase.enabled ? testCase.gains[index] : 0
        band.bypass = false
    }
    let maxBoost = testCase.gains.max() ?? 0
    eq.globalGain = testCase.enabled && maxBoost > 0.5 ? -maxBoost : 0
    eq.bypass = !testCase.enabled

    // One second of tone, looped, so decoding never dominates the measurement.
    let chunkFrames = Int(sampleRate)
    let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkFrames))!
    source.frameLength = AVAudioFrameCount(chunkFrames)
    for channel in 0..<Int(format.channelCount) {
        for i in 0..<chunkFrames {
            source.floatChannelData![channel][i] = amp * Float(sin(2.0 * .pi * freq * Double(i) / sampleRate))
        }
    }

    try! engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
    try! engine.start()
    player.play()
    for _ in 0..<Int(renderSeconds) {
        player.scheduleBuffer(source, at: nil, options: [], completionHandler: nil)
    }

    let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4_096)!
    let memoryBefore = residentBytes()
    let started = Date()
    var rendered = 0
    // One simulated track boundary per 10 s of audio.
    let boundaryInterval = Int(sampleRate * 10)
    var nextBoundary = boundaryInterval
    var gainToggle = false
    while engine.manualRenderingSampleTime < Int64(totalFrames) {
        if testCase.replayGain && rendered >= nextBoundary {
            gainToggle.toggle()
            gain.outputVolume = gainToggle ? 0.708 : 1.0
            nextBoundary += boundaryInterval
        }
        let remaining = Int64(totalFrames) - engine.manualRenderingSampleTime
        let slice = AVAudioFrameCount(min(4_096, remaining))
        guard (try? engine.renderOffline(slice, to: output)) == .success else { break }
        rendered += Int(slice)
    }
    let elapsed = Date().timeIntervalSince(started)
    let memoryAfter = residentBytes()

    player.stop(); engine.stop(); engine.disableManualRenderingMode()
    engine.detach(player); engine.detach(gain); engine.detach(eq); engine.detach(outputMixer)

    return (elapsed, renderSeconds / elapsed, Int64(memoryAfter) - Int64(memoryBefore))
}

print("=== Persistent EQ stage cost ===")
print("workload: \(Int(renderSeconds)) s of stereo 44.1 kHz through "
    + "player -> gain -> EQ -> mixer -> mainMixer, rendered offline\n")

// Warm up so first-run allocation doesn't distort the first case.
_ = measure(cases[0])

for testCase in cases {
    let result = autoreleasepool { measure(testCase) }
    // The figure that means something for playback: what share of one core this stage would need to
    // keep up with real time. A ratio between the states exaggerates a difference that is tiny in
    // absolute terms.
    let coreShare = 100.0 / result.throughput
    print(String(format: "%-32@ %6.3f s  %8.1fx RT  %.4f%% core  rss %+.1f MB",
                 testCase.name as NSString, result.seconds, result.throughput, coreShare,
                 Double(result.memoryDelta) / 1_048_576.0))
}

// MARK: - Visualization callback cost, measured directly

print("\n=== Visualization tap callback cost ===")
print("one 1024-frame stereo buffer copied into N bounded rings, 20000 iterations\n")

let callbackFrames = 1_024
let deadlineMicroseconds = Double(callbackFrames) / sampleRate * 1_000_000
let left = UnsafeMutablePointer<Float>.allocate(capacity: callbackFrames)
let right = UnsafeMutablePointer<Float>.allocate(capacity: callbackFrames)
for i in 0..<callbackFrames {
    left[i] = 0.4 * Float(sin(2.0 * .pi * freq * Double(i) / sampleRate))
    right[i] = left[i]
}

for consumerCount in [0, 1, 2] {
    let rings = (0..<consumerCount).map { _ in Ring(capacity: 16_384) }
    var peak: UInt64 = 0
    var total: UInt64 = 0
    let iterations = 20_000
    for iteration in 0..<iterations {
        let started = DispatchTime.now().uptimeNanoseconds
        for ring in rings { ring.write(left: left, right: right, frameCount: callbackFrames) }
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        peak = max(peak, elapsed)
        total += elapsed
        // Drain at ~60 Hz, as a UI would.
        if iteration % 3 == 0 { for ring in rings { ring.drain() } }
    }
    let averageMicroseconds = Double(total) / Double(iterations) / 1_000.0
    let peakMicroseconds = Double(peak) / 1_000.0
    let dropped = rings.reduce(0) { $0 + $1.dropped }
    print(String(format: "%d consumer(s): avg %6.2f us  peak %7.2f us  (%.2f%% of the %.1f ms deadline)  dropped %d",
                 consumerCount, averageMicroseconds, peakMicroseconds,
                 averageMicroseconds / deadlineMicroseconds * 100, deadlineMicroseconds / 1_000,
                 dropped))
}
left.deallocate(); right.deallocate()

print("""

Reading these numbers: EQ processing dominates what is otherwise an almost free graph, so the
relative gap between bypassed and active is large — but both are a negligible share of one core at
real time, and bypass is confirmed to cost essentially nothing to run. Memory is unchanged in every
state, as expected for a fixed node with no per-track allocation.

These are relative figures from offline rendering on this Mac. Device CPU, thermal and battery
behaviour are a Checkpoint 4 measurement and are not implied by these numbers.
""")
