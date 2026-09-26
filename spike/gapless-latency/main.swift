// Transport and callback latency distributions for the persistent engine.
//
// Run: swift spike/gapless-latency/main.swift
//
// Publishes min / median / p95 / max with an explicit sample count for each measurement, because a
// maximum alone hides whether a slow case is typical or a one-off, and an average alone hides the
// tail entirely.
//
// These are HOST-MACHINE results. Device CPU, thermal and battery are a Checkpoint 4 measurement and
// are not implied by anything here.

import AVFoundation
import Foundation

let sampleRate = 44_100.0
let trackFrames = 8_820          // 0.2 s per track
let tones: [Double] = [233, 379, 611, 977]

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

struct Distribution {
    let name: String
    let samples: [Double]

    var count: Int { samples.count }
    var minimum: Double { samples.min() ?? 0 }
    var maximum: Double { samples.max() ?? 0 }
    var median: Double { percentile(0.50) }
    var p95: Double { percentile(0.95) }

    func percentile(_ fraction: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[index]
    }

    func line(unit: String, scale: Double) -> String {
        String(format: "%-26@ n=%-5d  min %8.3f  med %8.3f  p95 %8.3f  max %8.3f  %@",
               name as NSString, count, minimum * scale, median * scale, p95 * scale,
               maximum * scale, unit as NSString)
    }
}

// MARK: - Fixtures

let work = FileManager.default.temporaryDirectory
    .appendingPathComponent("glat-\(getpid())", isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

func writeWav(_ url: URL, frequency: Double, frames: Int) throws {
    var samples = [Int16](repeating: 0, count: frames)
    for i in 0..<frames {
        samples[i] = Int16((max(-1, min(1, 0.5 * sin(2.0 * .pi * frequency * Double(i) / sampleRate))) * 32767).rounded())
    }
    let rate = UInt32(sampleRate), channels: UInt16 = 1, bits: UInt16 = 16
    let blockAlign = channels * bits / 8
    let dataSize = UInt32(samples.count * 2)
    var data = Data()
    func ascii(_ t: String) { data.append(contentsOf: Array(t.utf8)) }
    func u32(_ v: UInt32) { var l = v.littleEndian; withUnsafeBytes(of: &l) { data.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { var l = v.littleEndian; withUnsafeBytes(of: &l) { data.append(contentsOf: $0) } }
    ascii("RIFF"); u32(36 + dataSize); ascii("WAVE"); ascii("fmt "); u32(16); u16(1)
    u16(channels); u32(rate); u32(rate * UInt32(blockAlign)); u16(blockAlign); u16(bits)
    ascii("data"); u32(dataSize)
    samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
    try data.write(to: url)
}

var files: [URL] = []
for (index, tone) in tones.enumerated() {
    let url = work.appendingPathComponent("t\(index).wav")
    try writeWav(url, frequency: tone, frames: trackFrames)
    files.append(url)
}

// MARK: - Graph

/// Build the same graph shape the engine uses.
func makeGraph() -> (AVAudioEngine, AVAudioPlayerNode, AVAudioUnitEQ, AVAudioMixerNode, AVAudioMixerNode) {
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
    return (engine, player, eq, gain, outputMixer)
}

print("=== Persistent engine latency distributions (HOST machine) ===")
print("tracks: \(tones.count) x \(trackFrames) frames (\(Double(trackFrames) / sampleRate) s)\n")

// MARK: - Tail replacement latency

/// The mechanism behind Next, Previous, seek, Play Next and queue replacement: stop the node,
/// re-schedule from the audible position.
func measureTailReplacement(iterations: Int) throws -> Distribution {
    let (engine, player, _, _, _) = makeGraph()
    engine.prepare()
    try engine.start()
    defer { player.stop(); engine.stop() }
    let audioFiles = try files.map { try AVAudioFile(forReading: $0) }
    for file in audioFiles { player.scheduleFile(file, at: nil, completionHandler: nil) }
    player.play()

    var samples: [Double] = []
    for index in 0..<iterations {
        let started = DispatchTime.now().uptimeNanoseconds
        player.stop()
        let file = audioFiles[index % audioFiles.count]
        player.scheduleFile(file, at: nil, completionHandler: nil)
        player.play()
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
    }
    return Distribution(name: "tail replacement", samples: samples)
}

// MARK: - Scheduling latency

func measureScheduling(iterations: Int) throws -> Distribution {
    let (engine, player, _, _, _) = makeGraph()
    engine.prepare()
    try engine.start()
    defer { player.stop(); engine.stop() }
    var samples: [Double] = []
    for index in 0..<iterations {
        let file = try AVAudioFile(forReading: files[index % files.count])
        let started = DispatchTime.now().uptimeNanoseconds
        player.scheduleSegment(file, startingFrame: 0, frameCount: AVAudioFrameCount(trackFrames),
                               at: nil, completionCallbackType: .dataRendered) { _ in }
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
    }
    return Distribution(name: "schedule segment", samples: samples)
}

// MARK: - Preparation latency

func measurePreparation(iterations: Int) throws -> Distribution {
    var samples: [Double] = []
    for index in 0..<iterations {
        let started = DispatchTime.now().uptimeNanoseconds
        let file = try AVAudioFile(forReading: files[index % files.count])
        _ = file.length
        _ = file.processingFormat
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
    }
    return Distribution(name: "prepare (open+describe)", samples: samples)
}

// MARK: - Visualizer callback cost

/// The ring write the real feed performs, measured directly — under offline rendering the engine
/// batches tap callbacks, so timings taken there describe the rendering mode, not playback.
final class Ring {
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let mask: Int
    private var head = 0
    init(capacity: Int) {
        self.capacity = capacity
        mask = capacity - 1
        storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity * 2)
        storage.initialize(repeating: 0, count: capacity * 2)
    }
    deinit { storage.deallocate() }
    func write(_ left: UnsafePointer<Float>, _ right: UnsafePointer<Float>, _ frames: Int) {
        for i in 0..<frames {
            let slot = ((head + i) & mask) * 2
            storage[slot] = left[i]
            storage[slot + 1] = right[i]
        }
        head += frames
    }
}

func measureVisualizerCallback(consumers: Int, iterations: Int) -> Distribution {
    let frames = 1_024
    let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    defer { left.deallocate(); right.deallocate() }
    for i in 0..<frames { left[i] = 0.4 * Float(sin(Double(i) * 0.01)); right[i] = left[i] }
    let rings = (0..<consumers).map { _ in Ring(capacity: 16_384) }

    var samples: [Double] = []
    for _ in 0..<iterations {
        let started = DispatchTime.now().uptimeNanoseconds
        for ring in rings { ring.write(left, right, frames) }
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
    }
    return Distribution(name: "visualizer cb (\(consumers))", samples: samples)
}

// MARK: - Run

let memoryBaseline = residentBytes()
var distributions: [Distribution] = []
distributions.append(try measureTailReplacement(iterations: 250))
distributions.append(try measureScheduling(iterations: 500))
distributions.append(try measurePreparation(iterations: 500))
distributions.append(measureVisualizerCallback(consumers: 0, iterations: 5_000))
distributions.append(measureVisualizerCallback(consumers: 1, iterations: 5_000))
distributions.append(measureVisualizerCallback(consumers: 2, iterations: 5_000))

print("-- latency (milliseconds)")
for distribution in distributions {
    print("   " + distribution.line(unit: "ms", scale: 1_000))
}

let deadlineSeconds = Double(1_024) / sampleRate
print(String(format: "\n   audio deadline for a 1024-frame buffer: %.2f ms", deadlineSeconds * 1_000))
if let twoConsumers = distributions.first(where: { $0.name.contains("(2)") }) {
    print(String(format: "   two-consumer callback p95 uses %.3f%% of that deadline",
                 twoConsumers.p95 / deadlineSeconds * 100))
}

let memoryAfter = residentBytes()
print(String(format: "\n-- memory: baseline %.1f MB, after %.1f MB, delta %+.1f MB",
             Double(memoryBaseline) / 1_048_576, Double(memoryAfter) / 1_048_576,
             Double(Int64(memoryAfter) - Int64(memoryBaseline)) / 1_048_576))

print("""

HOST-MACHINE results. Transport figures measure the engine operation itself, not the wall-clock time
until audio is heard — that includes the hardware buffer, which is a device property. Device CPU,
thermal and battery remain a Checkpoint 4 measurement.
""")
