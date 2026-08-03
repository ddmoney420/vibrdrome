// How long must a ReplayGain change at a track boundary ramp to avoid a click?
//
// Run: swift spike/gapless-replaygain-ramp/main.swift
//
// A gain change applied in one sample is a step discontinuity — a click — even when the audio
// scheduling either side of it is frame-perfect. But a long fade smears the musical join, which is
// exactly what a gapless album must not do. So this measures the shortest ramp that removes the
// step, rather than picking a duration by feel.
//
// Method: one continuous tone crosses a "boundary" at a known frame. At that frame the gain changes
// from A to B, ramped over N ms in audio time. The worst sample-to-sample delta in a window around
// the boundary is compared with the signal's own in-cycle delta at the post-boundary level — a step
// shows up as a spike far above it.

import AVFoundation
import Foundation

let sampleRate = 44_100.0
let toneFreq = 220.0
let amp: Float = 0.4
let boundaryFrame = 44_100          // 1.0 s in
let totalFrames = 88_200            // 2.0 s

/// Gain pairs worth checking: the worst realistic jumps ReplayGain can produce, given the project's
/// 1.5x cap and the -12...+12 dB range of tagged material.
let transitions: [(name: String, from: Float, to: Float)] = [
    ("same gain (0 dB -> 0 dB)", 1.0, 1.0),
    ("+6 dB -> 0 dB", 1.995, 1.0),
    ("0 dB -> -6 dB", 1.0, 0.501),
    ("-12 dB -> +12 dB (capped 1.5x)", 0.251, 1.5),
    ("1.5x -> 0.25x (worst case)", 1.5, 0.251)
]

let rampMilliseconds: [Double] = [0, 2, 5, 10, 20]

/// Render a continuous tone through a gain node, changing gain at `boundaryFrame` over `rampMS`.
func render(from: Float, to: Float, rampMS: Double) -> [Float] {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                               channels: 1, interleaved: false)!
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let gain = AVAudioMixerNode()
    engine.attach(player); engine.attach(gain)
    engine.connect(player, to: gain, format: format)
    engine.connect(gain, to: engine.mainMixerNode, format: format)
    gain.outputVolume = from

    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
    buffer.frameLength = AVAudioFrameCount(totalFrames)
    for i in 0..<totalFrames {
        buffer.floatChannelData![0][i] = amp * Float(sin(2.0 * .pi * toneFreq * Double(i) / sampleRate))
    }

    // Small slices so the ramp can be stepped finely in audio time.
    let slice: AVAudioFrameCount = 16
    try! engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: slice)
    try! engine.start()
    player.play()
    player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)

    let rampFrames = Int(rampMS / 1000.0 * sampleRate)
    let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: slice)!
    var samples: [Float] = []
    while engine.manualRenderingSampleTime < Int64(totalFrames) {
        let now = samples.count
        if now >= boundaryFrame {
            if rampFrames == 0 {
                gain.outputVolume = to
            } else {
                let progress = min(1.0, Float(now - boundaryFrame) / Float(rampFrames))
                gain.outputVolume = from + (to - from) * progress
            }
        }
        let count = AVAudioFrameCount(min(Int64(slice), Int64(totalFrames) - engine.manualRenderingSampleTime))
        guard (try? engine.renderOffline(count, to: output)) == .success else { break }
        if let channel = output.floatChannelData?[0] {
            for i in 0..<Int(output.frameLength) { samples.append(channel[i]) }
        }
    }
    player.stop(); engine.stop(); engine.disableManualRenderingMode()
    engine.detach(player); engine.detach(gain)
    return samples
}

/// Worst sample-to-sample delta in a window spanning the boundary and the ramp.
func worstDelta(_ samples: [Float], around frame: Int, span: Int) -> (delta: Float, index: Int) {
    let lo = max(1, frame - 64), hi = min(samples.count - 1, frame + span + 64)
    var worst: Float = 0, worstIndex = lo
    for i in lo..<hi {
        let delta = abs(samples[i + 1] - samples[i])
        if delta > worst { worst = delta; worstIndex = i }
    }
    return (worst, worstIndex)
}

print("=== ReplayGain boundary ramp ===")
print("continuous \(Int(toneFreq)) Hz tone, gain change at frame \(boundaryFrame)\n")

for transition in transitions {
    // The reference is the signal's own movement at the louder of the two levels — a ramp is only
    // "clean" if it never exceeds what the music itself already does.
    let level = max(transition.from, transition.to)
    let inCycle = amp * level * 2 * Float(sin(Double.pi * toneFreq / sampleRate))
    print("-- \(transition.name)   in-cycle delta at peak level: \(String(format: "%.6f", inCycle))")
    for rampMS in rampMilliseconds {
        let samples = render(from: transition.from, to: transition.to, rampMS: rampMS)
        let span = Int(rampMS / 1000.0 * sampleRate)
        let (delta, index) = worstDelta(samples, around: boundaryFrame, span: span)
        let verdict = delta <= inCycle * 1.05 ? "clean" : "STEP"
        print(String(format: "   ramp %5.1f ms: worst %.6f @%d  (%.2fx in-cycle)  %@",
                     rampMS, delta, index, delta / inCycle, verdict))
    }
    print("")
}

print("""
A ramp is judged clean when the worst delta across the boundary is no larger than the tone's own
sample-to-sample movement at that level — i.e. the gain change is indistinguishable from the music.
""")
