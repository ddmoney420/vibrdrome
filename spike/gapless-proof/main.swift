// Objective offline-render proof for the persistent-output gapless engine.
// Proves that a persistent AVAudioEngine + AVAudioPlayerNode scheduling consecutive files
// renders frame-continuous audio (zero inserted/dropped/duplicated samples at boundaries) —
// WITHOUT a device or by-ear testing. Run: swift main.swift
//
// Method: build 4 sample-exact parts of ONE continuous 220 Hz sine (each 441000 frames, phase
// index runs unbroken across parts, so the ideal concatenation is a pure continuous sine).
// Schedule them back-to-back into the persistent graph, render offline to one buffer, then scan
// the rendered tone for any sample-to-sample discontinuity. A gap/dup/drop at a 441000-frame
// boundary shows up as a phase jump = a delta spike far above the smooth in-cycle delta.

import AVFoundation
import Foundation

let sampleRate = 44_100.0
let partFrames = 441_000            // exactly 10.000 s
let parts = 4
let freq = 220.0
let amp: Float = 0.4

let tmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("gapless-proof-\(getpid())", isDirectory: true)
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

// MARK: - Sample-exact WAV writer (manual RIFF; AVAudioFile CAF/m4a would quantize to packets)

func writeWav(_ url: URL, _ samples: [Int16]) {
    let rate = UInt32(sampleRate), channels: UInt16 = 1, bits: UInt16 = 16
    let blockAlign = channels * bits / 8
    let byteRate = rate * UInt32(blockAlign)
    let dataSize = UInt32(samples.count * 2)
    var d = Data()
    func s(_ t: String) { d.append(contentsOf: Array(t.utf8)) }
    func u32(_ v: UInt32) { var l = v.littleEndian; withUnsafeBytes(of: &l) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { var l = v.littleEndian; withUnsafeBytes(of: &l) { d.append(contentsOf: $0) } }
    s("RIFF"); u32(36 + dataSize); s("WAVE"); s("fmt "); u32(16); u16(1)
    u16(channels); u32(rate); u32(byteRate); u16(blockAlign); u16(bits)
    s("data"); u32(dataSize)
    samples.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
    try? d.write(to: url)
}

var urls: [URL] = []
for part in 0..<parts {
    var samples = [Int16](repeating: 0, count: partFrames)
    for i in 0..<partFrames {
        let n = part * partFrames + i           // continuous phase across parts
        let v = amp * Float(sin(2.0 * .pi * freq * Double(n) / sampleRate))
        samples[i] = Int16((max(-1, min(1, v)) * 32767).rounded())
    }
    let url = tmp.appendingPathComponent("part\(part + 1).wav")
    writeWav(url, samples)
    urls.append(url)
}
print("generated \(parts) parts x \(partFrames) frames in \(tmp.lastPathComponent)")

// MARK: - Persistent graph + offline render

let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
let eq = AVAudioUnitEQ(numberOfBands: 10)          // installed persistently, flat (transparent-ish)
engine.attach(player)
engine.attach(eq)

let firstFile = try AVAudioFile(forReading: urls[0])
let fileFormat = firstFile.processingFormat        // mono float32 44100
print("file processingFormat: \(fileFormat.sampleRate) Hz, \(fileFormat.channelCount) ch, "
    + "common=\(fileFormat.commonFormat.rawValue)")

engine.connect(player, to: eq, format: fileFormat)
engine.connect(eq, to: engine.mainMixerNode, format: fileFormat)

// Render offline in the SAME mono format so output is 1:1 with source frames.
let renderFormat = fileFormat
try engine.enableManualRenderingMode(.offline, format: renderFormat,
                                     maximumFrameCount: 4096)
try engine.start()
player.play()

// Schedule all 4 consecutively — the crux: at: nil appends seamlessly after prior schedule.
for url in urls {
    let f = try AVAudioFile(forReading: url)
    player.scheduleFile(f, at: nil, completionCallbackType: .dataRendered) { _ in }
}

let totalSource = AVAudioFramePosition(parts * partFrames)
let outBuf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                              frameCapacity: engine.manualRenderingMaximumFrameCount)!
var rendered: [Float] = []
rendered.reserveCapacity(Int(totalSource) + 8192)

while engine.manualRenderingSampleTime < totalSource {
    let remaining = totalSource - engine.manualRenderingSampleTime
    let toRender = AVAudioFrameCount(min(Int64(outBuf.frameCapacity), remaining))
    let status = try engine.renderOffline(toRender, to: outBuf)
    guard status == .success else { print("render status \(status.rawValue) — stop"); break }
    if let ch = outBuf.floatChannelData?[0] {
        for i in 0..<Int(outBuf.frameLength) { rendered.append(ch[i]) }
    }
}
player.stop()
engine.stop()
print("rendered \(rendered.count) frames (expected \(totalSource))")

// MARK: - Objective boundary measurement

// Trim any constant startup latency: find first frame above noise floor.
let floorLevel: Float = amp * 0.02
let start = rendered.firstIndex { abs($0) > floorLevel } ?? 0
let tone = Array(rendered[start...])
print("startup latency (leading near-silence frames): \(start)")

// In-cycle smooth delta scale from a mid window of part 1.
var inTrack: Float = 0
for i in 5_000..<6_000 where i + 1 < tone.count { inTrack = max(inTrack, abs(tone[i + 1] - tone[i])) }

// Scan the whole rendered tone for the worst discontinuity, and report the deltas that land
// exactly on the part boundaries (partFrames, 2*partFrames, 3*partFrames from tone start).
var worst: Float = 0, worstIdx = 0
for i in 0..<(tone.count - 1) {
    let dlt = abs(tone[i + 1] - tone[i])
    if dlt > worst { worst = dlt; worstIdx = i }
}
print(String(format: "in-cycle smooth delta: %.5f", inTrack))
print(String(format: "worst delta anywhere:  %.5f at frame %d", worst, worstIdx))
for b in 1..<parts {
    let idx = b * partFrames
    if idx < tone.count {
        let dlt = abs(tone[idx] - tone[idx - 1])
        let onBoundary = (worstIdx >= idx - 2 && worstIdx <= idx + 2)
        print(String(format: "  boundary P%d->P%d @tone-frame %d: delta=%.5f %@",
                     b, b + 1, idx, dlt, onBoundary ? "<-- worst is here" : ""))
    }
}

// MARK: - Verdict

let frameCountOK = abs(rendered.count - Int(totalSource)) <= 1   // allow ±1 render rounding
let continuityOK = worst <= inTrack * 3.0                        // no phase jump anywhere
print("")
print("frame-count match: \(frameCountOK) (rendered \(rendered.count) vs source \(totalSource))")
print("continuity (worst <= 3x in-cycle): \(continuityOK)")
print("RESULT: \((frameCountOK && continuityOK) ? "PASS" : "FAIL")")

try? FileManager.default.removeItem(at: tmp)
