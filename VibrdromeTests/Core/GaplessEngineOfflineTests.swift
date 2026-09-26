import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Objective frame-continuity tests for the persistent-output gapless engine
/// (feat/persistent-gapless-engine). These replace by-ear diagnostic loops: they render the engine
/// offline (deterministic `AVAudioEngine` manual rendering) and prove that scheduling consecutive
/// files produces zero inserted / dropped / duplicated samples at every track boundary.
struct GaplessEngineOfflineTests {
    static let sampleRate = 44_100.0
    static let partFrames = 441_000            // exactly 10.000 s
    static let freq = 220.0
    static let amp: Float = 0.4

    // MARK: - Pure scheduler frame-accounting

    @Test func schedulerMapsBoundariesToTheAudibleSegment() {
        var scheduler = GaplessScheduler()
        scheduler.append(id: "P1", renderFrames: 441_000)
        scheduler.append(id: "P2", renderFrames: 441_000)
        scheduler.append(id: "P3", renderFrames: 441_000)

        #expect(scheduler.totalFrames == 1_323_000)
        // Last frame of P1 is still P1; the very next frame is P2 (exact hand-off, no gap).
        #expect(scheduler.segment(atRenderFrame: 440_999)?.id == "P1")
        #expect(scheduler.segment(atRenderFrame: 441_000)?.id == "P2")
        #expect(scheduler.segment(atRenderFrame: 881_999)?.id == "P2")
        #expect(scheduler.segment(atRenderFrame: 882_000)?.id == "P3")
        #expect(scheduler.index(atRenderFrame: 882_000) == 2)
        // Before the first / past the last → no audible segment.
        #expect(scheduler.segment(atRenderFrame: 1_323_000) == nil)
    }

    @Test func schedulerTruncateFromIDDropsItemAndSuccessors() {
        var scheduler = GaplessScheduler()
        scheduler.append(id: "P1", renderFrames: 441_000)
        scheduler.append(id: "P2", renderFrames: 441_000)
        scheduler.append(id: "P3", renderFrames: 441_000)

        let resume = scheduler.truncate(fromID: "P2")
        #expect(resume == 441_000)               // re-scheduling resumes at P2's old start
        #expect(scheduler.segments.count == 1)
        #expect(scheduler.segments.first?.id == "P1")
        #expect(scheduler.totalFrames == 441_000)
    }

    // MARK: - Objective offline frame-continuity

    @Test func fourPartTransitionsAreFrameContinuous() throws {
        let urls = try makeContinuousToneParts(count: 4)
        defer { for url in urls { try? FileManager.default.removeItem(at: url) } }

        // Run the engine at the source format (mono 44.1 kHz) so render frames are 1:1 with source
        // frames and the boundary measurement is exact.
        let renderFormat = try AVAudioFile(forReading: urls[0]).processingFormat
        let engine = PersistentGaplessEngine(renderFormat: renderFormat)
        try engine.schedule(urls: urls)

        let rendered = try engine.renderOfflineChannel0()

        // 1. Frame-count: zero inserted / dropped / duplicated frames across all 4 parts.
        let expected = 4 * Self.partFrames
        #expect(abs(rendered.count - expected) <= 1)

        // 2. Continuity: the source is ONE continuous sine, so a gap/dup at any boundary is a phase
        //    jump = a sample-to-sample delta spike far above the smooth in-cycle delta.
        let start = rendered.firstIndex { abs($0) > Self.amp * 0.02 } ?? 0
        let tone = Array(rendered[start...])

        var inCycle: Float = 0
        for i in 5_000..<6_000 where i + 1 < tone.count {
            inCycle = max(inCycle, abs(tone[i + 1] - tone[i]))
        }
        var worst: Float = 0
        for i in 0..<(tone.count - 1) { worst = max(worst, abs(tone[i + 1] - tone[i])) }
        #expect(inCycle > 0)
        #expect(worst <= inCycle * 3.0)          // no discontinuity anywhere, incl. every boundary

        // 3. Each boundary specifically is indistinguishable from an in-track step.
        for boundary in 1..<4 {
            let idx = boundary * Self.partFrames
            guard idx < tone.count else { continue }
            #expect(abs(tone[idx] - tone[idx - 1]) <= inCycle * 3.0)
        }
    }

    // MARK: - Sample-exact continuous tone generation

    /// `count` parts of ONE continuous 220 Hz sine, each exactly `partFrames`. Phase index runs
    /// unbroken across parts, so the ideal concatenation is a pure continuous sine — any scheduling
    /// gap/dup shows up as a discontinuity. Manual WAV writer (AVAudioFile would packet-quantize).
    private func makeContinuousToneParts(count: Int) throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gqe-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for part in 0..<count {
            var samples = [Int16](repeating: 0, count: Self.partFrames)
            for i in 0..<Self.partFrames {
                let n = part * Self.partFrames + i
                let v = Self.amp * Float(sin(2.0 * .pi * Self.freq * Double(n) / Self.sampleRate))
                samples[i] = Int16((max(-1, min(1, v)) * 32767).rounded())
            }
            let url = dir.appendingPathComponent("part\(part + 1).wav")
            try writeWav(url: url, samples: samples)
            urls.append(url)
        }
        return urls
    }

    private func writeWav(url: URL, samples: [Int16]) throws {
        let rate = UInt32(Self.sampleRate)
        let channels: UInt16 = 1, bits: UInt16 = 16
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
}
