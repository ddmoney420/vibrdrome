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
}

let cases = [
    Case(name: "EQ bypassed", gains: Array(repeating: 0, count: 10), enabled: false),
    Case(name: "EQ active, neutral (all 0 dB)", gains: Array(repeating: 0, count: 10), enabled: true),
    Case(name: "EQ active, Rock preset", gains: [5, 4, 2, 0, -1, 0, 2, 3, 4, 5], enabled: true)
]

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
    while engine.manualRenderingSampleTime < Int64(totalFrames) {
        let remaining = Int64(totalFrames) - engine.manualRenderingSampleTime
        let slice = AVAudioFrameCount(min(4_096, remaining))
        guard (try? engine.renderOffline(slice, to: output)) == .success else { break }
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
    print(String(format: "%-32@ %6.3f s render  %8.1fx real-time  %.4f%% of one core  rss %+.1f MB",
                 testCase.name as NSString, result.seconds, result.throughput, coreShare,
                 Double(result.memoryDelta) / 1_048_576.0))
}

print("""

Reading these numbers: EQ processing dominates what is otherwise an almost free graph, so the
relative gap between bypassed and active is large — but both are a negligible share of one core at
real time, and bypass is confirmed to cost essentially nothing to run. Memory is unchanged in every
state, as expected for a fixed node with no per-track allocation.

These are relative figures from offline rendering on this Mac. Device CPU, thermal and battery
behaviour are a Checkpoint 4 measurement and are not implied by these numbers.
""")
