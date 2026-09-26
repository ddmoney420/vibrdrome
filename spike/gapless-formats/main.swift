// Per-format frame-continuity matrix for the persistent-output gapless engine.
//
// Checkpoint 3 item 1 asks: does the cached-file -> decode -> schedule pipeline stay
// frame-continuous for every format Vibrdrome actually plays (direct FLAC / ALAC / AAC / MP3,
// server-transcoded, downloaded)? This measures it objectively, with no device and no ears.
//
// Run:  swift spike/gapless-formats/main.swift [--keep] [extra album dir ...]
//
// Method
// ------
// 1. Generate ONE continuous 220 Hz sine split into 4 sample-exact 10.000 s parts (the same
//    material as the real ~/vibrdrome-test-media albums), then encode that split with ffmpeg into
//    each candidate delivery format. Every part is encoded INDEPENDENTLY -- exactly how a server
//    stores tracks and how Navidrome transcodes them, so codec priming/padding lands on every join.
// 2. For each format, read each part with AVAudioFile and record its DECODED length. This is the
//    decisive number: `scheduleFile` schedules exactly `file.length` frames, so
//    (decoded - expected) is the count of frames the codec inserts at that join. Exact, not
//    estimated. Expected frames are computed at the FILE's own sample rate (Opus decodes at 48 kHz).
// 3. Schedule all 4 parts consecutively into a persistent AVAudioEngine graph, render offline, and
//    measure the rendered tone: total frames, worst sample-to-sample delta, and a phase measurement
//    at each boundary (I/Q demodulation at the tone frequency) that converts the phase step into a
//    fractional frame offset. Phase is robust to lossy-codec noise, unlike a raw delta threshold.
// 4. For MP3, ALSO measure the trimmed path: parse the Xing/LAME gapless header for encoder delay
//    and padding and schedule the trimmed segment instead of the whole file. This is the candidate
//    production fix -- the matrix proves whether it restores frame continuity.
//
// A format PASSES when every part decodes to exactly the expected frame count AND every boundary is
// phase-continuous (|frame offset| < 1) AND the total rendered frame count matches.

import AVFoundation
import Foundation

// MARK: - Configuration

let masterSampleRate = 44_100.0
let partSeconds = 10.0
let partFrames = Int(masterSampleRate * partSeconds)   // 441000, exactly 10.000 s
let partCount = 4
let toneFreq = 220.0
let toneAmp: Float = 0.4

let args = Array(CommandLine.arguments.dropFirst())
let keepArtifacts = args.contains("--keep")
/// Skip the synthetic encode matrix and measure only the real albums on disk.
let realOnly = args.contains("--real-only")
let extraAlbumDirs = args.filter { !$0.hasPrefix("--") }

let work = FileManager.default.temporaryDirectory
    .appendingPathComponent("gapless-formats-\(getpid())", isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

// MARK: - Shell

@discardableResult
func run(_ launchPath: String, _ arguments: [String], stdoutTo: URL? = nil) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let pipe = Pipe()
    if let stdoutTo {
        FileManager.default.createFile(atPath: stdoutTo.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: stdoutTo) else { return (-1, "cannot open output") }
        process.standardOutput = handle
    } else {
        process.standardOutput = pipe
    }
    process.standardError = pipe
    do { try process.run() } catch { return (-1, "launch failed: \(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func which(_ tool: String) -> String? {
    for candidate in ["/opt/homebrew/bin/\(tool)", "/usr/local/bin/\(tool)", "/usr/bin/\(tool)"]
    where FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
    }
    return nil
}

guard let ffmpeg = which("ffmpeg") else {
    print("ffmpeg not found (brew install ffmpeg) — cannot build the format matrix.")
    exit(2)
}

// MARK: - Sample-exact WAV master (manual RIFF; encoders quantize, WAV must not)

func writeWav(_ url: URL, _ samples: [Int16]) throws {
    let rate = UInt32(masterSampleRate), channels: UInt16 = 1, bits: UInt16 = 16
    let blockAlign = channels * bits / 8
    let dataSize = UInt32(samples.count * 2)
    var data = Data()
    func ascii(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
    func u32(_ value: UInt32) { var l = value.littleEndian; withUnsafeBytes(of: &l) { data.append(contentsOf: $0) } }
    func u16(_ value: UInt16) { var l = value.littleEndian; withUnsafeBytes(of: &l) { data.append(contentsOf: $0) } }
    ascii("RIFF"); u32(36 + dataSize); ascii("WAVE"); ascii("fmt "); u32(16); u16(1)
    u16(channels); u32(rate); u32(rate * UInt32(blockAlign)); u16(blockAlign); u16(bits)
    ascii("data"); u32(dataSize)
    samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
    try data.write(to: url)
}

var wavParts: [URL] = []
for part in 0..<partCount {
    var samples = [Int16](repeating: 0, count: partFrames)
    for i in 0..<partFrames {
        let n = part * partFrames + i                     // phase runs unbroken across parts
        let v = toneAmp * Float(sin(2.0 * .pi * toneFreq * Double(n) / masterSampleRate))
        samples[i] = Int16((max(-1, min(1, v)) * 32767).rounded())
    }
    let url = work.appendingPathComponent("wav/part\(part + 1).wav")
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try writeWav(url, samples)
    wavParts.append(url)
}

// MARK: - Xing / LAME gapless header (the MP3 fix)

/// Encoder delay + padding declared by an MP3's Xing/Info+LAME header. AVAudioFile does NOT apply
/// these — it hands back delay + audio + padding — so a whole-file `scheduleFile` inserts
/// (delay + padding) frames of encoder junk at every join. Trimming to
/// [delay, length - padding) is the candidate production fix.
struct MP3GaplessInfo {
    let encoderDelay: Int
    let padding: Int
}

func readMP3GaplessInfo(_ url: URL) -> MP3GaplessInfo? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 200 else { return nil }
    var offset = 0

    // Skip an ID3v2 tag if present: "ID3" + ver(2) + flags(1) + syncsafe size(4).
    if data.count > 10, data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 {
        let size = (Int(data[6]) << 21) | (Int(data[7]) << 14) | (Int(data[8]) << 7) | Int(data[9])
        offset = 10 + size
        if data[5] & 0x10 != 0 { offset += 10 }          // footer present
    }
    guard offset + 4 < data.count else { return nil }

    // First MPEG audio frame header — the Xing/Info tag lives inside it.
    guard data[offset] == 0xFF, data[offset + 1] & 0xE0 == 0xE0 else { return nil }
    let versionBits = (data[offset + 1] >> 3) & 0x03      // 0b11 = MPEG1, 0b10 = MPEG2, 0b00 = MPEG2.5
    let channelMode = (data[offset + 3] >> 6) & 0x03      // 0b11 = mono
    let isMPEG1 = versionBits == 0x03
    let isMono = channelMode == 0x03
    let sideInfo: Int
    switch (isMPEG1, isMono) {
    case (true, true): sideInfo = 17
    case (true, false): sideInfo = 32
    case (false, true): sideInfo = 9
    case (false, false): sideInfo = 17
    }

    var pos = offset + 4 + sideInfo
    guard pos + 8 <= data.count else { return nil }
    let tag = String(bytes: data[pos..<(pos + 4)], encoding: .ascii)
    guard tag == "Xing" || tag == "Info" else { return nil }
    pos += 4

    let flags = (Int(data[pos]) << 24) | (Int(data[pos + 1]) << 16) | (Int(data[pos + 2]) << 8) | Int(data[pos + 3])
    pos += 4
    if flags & 0x01 != 0 { pos += 4 }                     // frame count
    if flags & 0x02 != 0 { pos += 4 }                     // byte count
    if flags & 0x04 != 0 { pos += 100 }                   // seek TOC
    if flags & 0x08 != 0 { pos += 4 }                     // VBR quality

    // LAME extension: 9-byte version string, then fixed fields; delay/padding sit at +21.
    guard pos + 24 <= data.count else { return nil }
    guard let encoder = String(bytes: data[pos..<(pos + 4)], encoding: .ascii),
          encoder == "LAME" || encoder == "Lavc" || encoder == "Lavf" else { return nil }
    let delayByte0 = Int(data[pos + 21]), delayByte1 = Int(data[pos + 22]), padByte = Int(data[pos + 23])
    let delay = (delayByte0 << 4) | (delayByte1 >> 4)
    let padding = ((delayByte1 & 0x0F) << 8) | padByte
    guard delay >= 0, padding >= 0, delay < 10_000, padding < 10_000 else { return nil }
    return MP3GaplessInfo(encoderDelay: delay, padding: padding)
}

// MARK: - Format matrix (each part encoded independently, like real server-side files)

struct FormatCase {
    let name: String
    let note: String
    let ext: String
    let encodeArgs: [String]
    /// Encode through a pipe instead of a seekable file — mimics a live server-side transcode,
    /// where the encoder cannot seek back to finalise its gapless header.
    var viaPipe = false
    /// Apply the Xing/LAME trim before scheduling.
    var trimMP3 = false
}

let formatCases: [FormatCase] = [
    FormatCase(name: "WAV (control)", note: "no codec — baseline", ext: "wav", encodeArgs: ["-c:a", "pcm_s16le"]),
    FormatCase(name: "FLAC (direct)", note: "lossless, direct play", ext: "flac", encodeArgs: ["-c:a", "flac"]),
    FormatCase(name: "ALAC (direct)", note: "lossless m4a, direct play", ext: "m4a", encodeArgs: ["-c:a", "alac"]),
    FormatCase(name: "AAC (direct)", note: "lossy m4a, direct play", ext: "m4a",
               encodeArgs: ["-c:a", "aac", "-b:a", "256k"]),
    FormatCase(name: "MP3 (direct, untrimmed)", note: "lossy, whole-file scheduleFile", ext: "mp3",
               encodeArgs: ["-c:a", "libmp3lame", "-b:a", "320k"]),
    FormatCase(name: "MP3 (direct, LAME-trimmed)", note: "candidate fix: trim delay+padding", ext: "mp3",
               encodeArgs: ["-c:a", "libmp3lame", "-b:a", "320k"], trimMP3: true),
    FormatCase(name: "MP3 320 transcode (file)", note: "Navidrome transcode, seekable output", ext: "mp3",
               encodeArgs: ["-c:a", "libmp3lame", "-b:a", "320k"], trimMP3: true),
    FormatCase(name: "MP3 320 transcode (piped)", note: "live stream transcode — no seek-back", ext: "mp3",
               encodeArgs: ["-c:a", "libmp3lame", "-b:a", "320k", "-f", "mp3"], viaPipe: true, trimMP3: true),
    FormatCase(name: "Opus 192 transcode", note: "Navidrome opus target (decodes at 48 kHz)", ext: "opus",
               encodeArgs: ["-c:a", "libopus", "-b:a", "192k"])
]

func encodeAlbum(_ format: FormatCase, index: Int) -> [URL]? {
    let dir = work.appendingPathComponent("fmt\(index)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var urls: [URL] = []
    for (i, source) in wavParts.enumerated() {
        let out = dir.appendingPathComponent("part\(i + 1).\(format.ext)")
        let target = format.viaPipe ? "pipe:1" : out.path
        let result = run(ffmpeg, ["-y", "-hide_banner", "-loglevel", "error",
                                  "-i", source.path] + format.encodeArgs + [target],
                         stdoutTo: format.viaPipe ? out : nil)
        guard result.status == 0, FileManager.default.fileExists(atPath: out.path) else {
            print("   encode failed: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            return nil
        }
        urls.append(out)
    }
    return urls
}

// MARK: - Persistent graph offline render (mirrors PersistentGaplessEngine)

/// One scheduled item: the decoded file plus the frame range actually scheduled.
struct ScheduledItem {
    let decodedLength: AVAudioFramePosition
    let startFrame: AVAudioFramePosition
    let frameCount: AVAudioFrameCount
    var scheduledFrames: AVAudioFramePosition { AVAudioFramePosition(frameCount) }
}

/// Schedule `urls` consecutively into ONE persistent AVAudioEngine graph and render offline.
/// When `trimMP3` is set, each file is scheduled as a segment with the Xing/LAME encoder delay and
/// padding removed instead of whole-file.
///
/// Each render tears its graph down completely (stop, disable manual rendering, detach nodes) inside
/// an autorelease pool. Without that, a process that builds many engines in a row starts producing
/// corrupted renders — measured here as a phantom discontinuity on a file set that renders clean in
/// isolation. That is a harness artifact, not an engine defect; the teardown removes it.
func renderConsecutively(_ urls: [URL], trimMP3: Bool) throws
    -> (samples: [Float], items: [ScheduledItem], sampleRate: Double, trims: [MP3GaplessInfo?]) {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let eq = AVAudioUnitEQ(numberOfBands: 10)            // persistent, flat
    engine.attach(player)
    engine.attach(eq)

    let files = try urls.map { try AVAudioFile(forReading: $0) }
    let renderFormat = files[0].processingFormat          // render 1:1 with decoded frames
    engine.connect(player, to: eq, format: renderFormat)
    engine.connect(eq, to: engine.mainMixerNode, format: renderFormat)

    try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)
    try engine.start()
    player.play()

    var items: [ScheduledItem] = []
    var trims: [MP3GaplessInfo?] = []
    for (index, file) in files.enumerated() {
        let info = trimMP3 ? readMP3GaplessInfo(urls[index]) : nil
        trims.append(info)
        let start = AVAudioFramePosition(info?.encoderDelay ?? 0)
        let count = AVAudioFrameCount(max(0, file.length - start - AVAudioFramePosition(info?.padding ?? 0)))
        items.append(ScheduledItem(decodedLength: file.length, startFrame: start, frameCount: count))
        if info == nil {
            player.scheduleFile(file, at: nil, completionCallbackType: .dataRendered) { _ in }
        } else {
            player.scheduleSegment(file, startingFrame: start, frameCount: count, at: nil,
                                   completionCallbackType: .dataRendered) { _ in }
        }
    }

    let total = items.reduce(AVAudioFramePosition(0)) { $0 + $1.scheduledFrames }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                        frameCapacity: engine.manualRenderingMaximumFrameCount) else {
        throw NSError(domain: "spike", code: 1)
    }
    var out: [Float] = []
    out.reserveCapacity(Int(total) + 8192)
    while engine.manualRenderingSampleTime < total {
        let remaining = total - engine.manualRenderingSampleTime
        let toRender = AVAudioFrameCount(min(Int64(buffer.frameCapacity), remaining))
        let status = try engine.renderOffline(toRender, to: buffer)
        guard status == .success else { break }
        if let channel = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) { out.append(channel[i]) }
        }
    }
    player.stop()
    engine.stop()
    engine.disableManualRenderingMode()
    engine.detach(player)
    engine.detach(eq)
    return (out, items, renderFormat.sampleRate, trims)
}

// MARK: - Measurement

/// Dominant tone frequency, so the tool works on any continuous-tone album without assuming 220 Hz.
func estimateFrequency(_ samples: [Float], from offset: Int, sampleRate: Double) -> Double {
    let window = min(Int(sampleRate), samples.count - offset)
    guard window > 4_000 else { return toneFreq }
    let slice = Array(samples[offset..<(offset + window)])
    func power(_ freq: Double) -> Double {
        var re = 0.0, im = 0.0
        let step = 2.0 * .pi * freq / sampleRate
        for (n, value) in slice.enumerated() {
            re += Double(value) * cos(step * Double(n))
            im += Double(value) * sin(step * Double(n))
        }
        return re * re + im * im
    }
    var best = toneFreq, bestPower = -1.0
    for hz in stride(from: 50.0, through: 2_000.0, by: 1.0) {
        let p = power(hz)
        if p > bestPower { bestPower = p; best = hz }
    }
    for hz in stride(from: best - 1.0, through: best + 1.0, by: 0.02) {
        let p = power(hz)
        if p > bestPower { bestPower = p; best = hz }
    }
    return best
}

/// Residual phase of the tone in a window, measured against the ideal continuous sine indexed by
/// absolute rendered frame. Constant across the whole render == no frames inserted or dropped.
func residualPhase(_ samples: [Float], center: Int, halfWidth: Int, freq: Double, sampleRate: Double) -> Double? {
    let lo = max(0, center - halfWidth), hi = min(samples.count, center + halfWidth)
    guard hi - lo > 512 else { return nil }
    var re = 0.0, im = 0.0
    let step = 2.0 * .pi * freq / sampleRate
    for n in lo..<hi {
        re += Double(samples[n]) * cos(step * Double(n))
        im += Double(samples[n]) * sin(step * Double(n))
    }
    return atan2(im, re)
}

struct Report {
    let name: String
    let note: String
    let items: [ScheduledItem]
    let trims: [MP3GaplessInfo?]
    let expectedFrames: AVAudioFramePosition
    let renderedFrames: Int
    let sampleRate: Double
    let inCycleDelta: Float
    let worstDelta: Float
    let boundaryFrameOffsets: [Double?]

    /// Frames actually handed to the player node per part vs the true source length.
    var scheduledExact: Bool { items.allSatisfy { $0.scheduledFrames == expectedFrames } }
    var totalInserted: AVAudioFramePosition {
        items.reduce(AVAudioFramePosition(0)) { $0 + $1.scheduledFrames } - expectedFrames * AVAudioFramePosition(items.count)
    }
    var phaseContinuous: Bool {
        !boundaryFrameOffsets.isEmpty && boundaryFrameOffsets.allSatisfy { offset in
            guard let offset else { return false }
            return abs(offset) < 1.0
        }
    }
    var pass: Bool { scheduledExact && phaseContinuous }
}

func measure(name: String, note: String, urls: [URL], trimMP3: Bool) throws -> Report {
    let (rendered, items, sampleRate, trims) = try autoreleasepool {
        try renderConsecutively(urls, trimMP3: trimMP3)
    }

    // Expected frames at the FILE's own rate — Opus decodes at 48 kHz, so 10.000 s is 480000 frames.
    let expected = AVAudioFramePosition((partSeconds * sampleRate).rounded())

    // Trim constant startup latency so absolute frame indices line up with the source timeline.
    let floorLevel = toneAmp * 0.02
    let start = rendered.firstIndex { abs($0) > floorLevel } ?? 0
    let tone = Array(rendered[start...])

    let freq = estimateFrequency(tone, from: 10_000, sampleRate: sampleRate)
    var inCycle: Float = 0
    for i in 5_000..<6_000 where i + 1 < tone.count { inCycle = max(inCycle, abs(tone[i + 1] - tone[i])) }
    var worst: Float = 0
    for i in 0..<(tone.count - 1) { worst = max(worst, abs(tone[i + 1] - tone[i])) }

    // Express each boundary's phase step in frames at the tone frequency.
    let radiansPerFrame = 2.0 * .pi * freq / sampleRate
    let guardWidth = Int(sampleRate * 0.5), halfWidth = Int(sampleRate * 0.2)
    var offsets: [Double?] = []
    var cumulative: AVAudioFramePosition = 0
    for boundary in 0..<(items.count - 1) {
        cumulative += items[boundary].scheduledFrames
        let idx = Int(cumulative)
        // Windows sit clear of the join so codec ring-out at the seam doesn't bias either side.
        guard idx + guardWidth + halfWidth < tone.count,
              let before = residualPhase(tone, center: idx - guardWidth, halfWidth: halfWidth,
                                         freq: freq, sampleRate: sampleRate),
              let after = residualPhase(tone, center: idx + guardWidth, halfWidth: halfWidth,
                                        freq: freq, sampleRate: sampleRate) else {
            offsets.append(nil); continue
        }
        var delta = after - before
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        offsets.append(delta / radiansPerFrame)
    }

    return Report(name: name, note: note, items: items, trims: trims, expectedFrames: expected,
                  renderedFrames: rendered.count, sampleRate: sampleRate, inCycleDelta: inCycle,
                  worstDelta: worst, boundaryFrameOffsets: offsets)
}

func printReport(_ report: Report) {
    let decoded = report.items.map { "\($0.decodedLength)" }.joined(separator: ", ")
    print("   sample rate: \(Int(report.sampleRate)) Hz · expected \(report.expectedFrames) frames/part")
    print("   decoded frames per part:   [\(decoded)]")
    if let first = report.trims.first, first != nil {
        let trimText = report.trims.map { info in
            info.map { "delay \($0.encoderDelay)/pad \($0.padding)" } ?? "no gapless header"
        }.joined(separator: ", ")
        print("   Xing/LAME header:          [\(trimText)]")
        let scheduled = report.items.map { "\($0.scheduledFrames)" }.joined(separator: ", ")
        print("   scheduled frames per part: [\(scheduled)]")
    }
    if report.scheduledExact {
        print("   frame exactness: EXACT — 0 frames inserted at any join")
    } else {
        let deltas = report.items.map { item -> String in
            let delta = item.scheduledFrames - report.expectedFrames
            return "\(delta >= 0 ? "+" : "")\(delta)"
        }
        print("   frame exactness: OFF BY [\(deltas.joined(separator: ", "))] — total "
            + "\(report.totalInserted) frames "
            + String(format: "(%.1f ms across the album)",
                     Double(report.totalInserted) / report.sampleRate * 1000))
    }
    print("   rendered frames: \(report.renderedFrames)")
    print(String(format: "   in-cycle delta %.5f · worst delta %.5f", report.inCycleDelta, report.worstDelta))
    for (i, offset) in report.boundaryFrameOffsets.enumerated() {
        if let offset {
            print(String(format: "   boundary %d->%d phase offset: %+.3f frames %@",
                         i + 1, i + 2, offset, abs(offset) < 1.0 ? "(continuous)" : "<-- DISCONTINUITY"))
        } else {
            print("   boundary \(i + 1)->\(i + 2) phase offset: not measurable")
        }
    }
    print("   \(report.pass ? "PASS" : "FAIL")\n")
}

// MARK: - Run the matrix

print("=== Gapless per-format frame-continuity matrix ===")
print("source: \(partCount) x \(partFrames) frames (\(partSeconds) s) of ONE continuous "
    + "\(Int(toneFreq)) Hz sine, each part encoded independently\n")

var reports: [Report] = []

for (index, format) in formatCases.enumerated() where !realOnly {
    print("-- \(format.name)  (\(format.note))")
    guard let urls = encodeAlbum(format, index: index) else {
        print("   SKIPPED (encoder unavailable)\n")
        continue
    }
    do {
        let report = try measure(name: format.name, note: format.note, urls: urls, trimMP3: format.trimMP3)
        reports.append(report)
        printReport(report)
    } catch {
        print("   FAILED to render: \(error)\n")
    }
}

// Real albums from the owner's test media (plus any extra dirs passed on the command line).
let home = FileManager.default.homeDirectoryForCurrentUser
let realAlbums: [(String, URL)] = [
    ("REAL FLAC album (test media)", home.appendingPathComponent("vibrdrome-test-media/Gapless 4-Track Test")),
    ("REAL ALAC album (test media)", home.appendingPathComponent("vibrdrome-test-media/Gapless 4-Track ALAC"))
] + extraAlbumDirs.map { ("REAL \(URL(fileURLWithPath: $0).lastPathComponent)", URL(fileURLWithPath: $0)) }

for (name, dir) in realAlbums {
    let audioExtensions: Set<String> = ["flac", "m4a", "mp3", "wav", "aac", "opus", "ogg"]
    guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
        print("-- \(name): directory not found (\(dir.path))\n")
        continue
    }
    let urls = contents.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.path < $1.path }
    guard urls.count >= 2 else { print("-- \(name): no album files found\n"); continue }
    print("-- \(name)  (\(urls.count) tracks from disk)")
    do {
        let report = try measure(name: name, note: "owner's real test album", urls: urls,
                                 trimMP3: urls[0].pathExtension.lowercased() == "mp3")
        reports.append(report)
        printReport(report)
    } catch {
        print("   FAILED to render: \(error)\n")
    }
}

// MARK: - Summary

print("=== SUMMARY ===")
for report in reports {
    let verdict = report.pass ? "PASS" : "FAIL"
    let detail = report.scheduledExact ? "frame-exact" : "off by \(report.totalInserted) frames"
    print("  \(verdict)  \(report.name) — \(detail)")
}
let allPass = reports.allSatisfy(\.pass)
print("")
print("RESULT: \(allPass ? "PASS" : "MIXED — see per-format detail above")")

if keepArtifacts {
    print("\nartifacts kept at \(work.path)")
} else {
    try? FileManager.default.removeItem(at: work)
}
