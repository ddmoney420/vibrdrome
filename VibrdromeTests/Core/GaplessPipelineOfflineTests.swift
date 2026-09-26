import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// End-to-end objective proof for the Checkpoint 3 streaming pipeline:
/// resolve to a local file -> decode -> prepare -> schedule into the persistent graph, then render
/// the whole thing offline and measure whether the joins are frame-continuous.
///
/// This exercises the *real* production types (`GaplessTrackPreparer`, `GaplessFileProviding`,
/// `PersistentGaplessEngine`) rather than a bespoke test rig, with the network replaced by a
/// provider that serves files from disk. Per-codec evidence (ALAC/FLAC/AAC/MP3/transcoded) lives in
/// `spike/gapless-formats/main.swift`, which needs ffmpeg and so cannot run in the simulator.
struct GaplessPipelineOfflineTests {
    static let sampleRate = 44_100.0
    static let partFrames = 44_100                // 1.000 s per part keeps the suite fast
    static let freq = 220.0
    static let amp: Float = 0.4

    // MARK: - Preparation

    @Test func preparesALocalTrackWithItsTrueDecodedLength() async throws {
        let urls = try Self.makeContinuousToneParts(count: 1)
        defer { Self.cleanUp(urls) }
        let provider = GaplessLocalFileProvider(albumFiles: urls)
        let preparer = GaplessTrackPreparer(provider: provider)

        let track = try await preparer.preparedTrack(urls[0].lastPathComponent)

        #expect(track.trim.frameCount == AVAudioFrameCount(Self.partFrames))
        #expect(track.trim.reason == .wholeFile)
        #expect(track.renderFrames == AVAudioFramePosition(Self.partFrames))
        #expect(track.matchesRenderRate)
        #expect(track.fileURL.isFileURL)
    }

    /// Sample-rate conversion changes the frame count, so the render-timeline count must be the
    /// converted one or every boundary after it lands on the wrong frame.
    @Test func recordsConvertedFrameCountForAMismatchedSampleRate() async throws {
        let urls = try Self.makeContinuousToneParts(count: 1, sampleRate: 48_000, frames: 48_000)
        defer { Self.cleanUp(urls) }
        let provider = GaplessLocalFileProvider(albumFiles: urls)
        let preparer = GaplessTrackPreparer(provider: provider, renderSampleRate: 44_100)

        let track = try await preparer.preparedTrack(urls[0].lastPathComponent)

        #expect(track.sourceSampleRate == 48_000)
        #expect(track.trim.frameCount == 48_000)               // source frames
        #expect(track.renderFrames == 44_100)                  // render-timeline frames
        #expect(!track.matchesRenderRate)
    }

    @Test func missingLocalFileIsReportedNotSilentlySkipped() async throws {
        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(filesByTrackID: [:]))

        await #expect(throws: GaplessPreparationError.self) {
            try await preparer.preparedTrack("absent")
        }
    }

    // MARK: - Rolling window

    @Test func windowPreparesCurrentAndNextAndReleasesPlayedTracks() async throws {
        let urls = try Self.makeContinuousToneParts(count: 4)
        defer { Self.cleanUp(urls) }
        let ids = urls.map(\.lastPathComponent)
        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(albumFiles: urls))

        let safeAtStart = await preparer.advanceWindow(queue: ids, currentIndex: 0)
        #expect(safeAtStart)
        var ready = await preparer.readyTrackIDs
        #expect(ready.contains(ids[0]))
        #expect(ready.contains(ids[1]))                        // next is ready before it is needed
        #expect(!ready.contains(ids[3]))                       // beyond the window

        // Advance two tracks: the played ones are released, the new ones prepared.
        let safeLater = await preparer.advanceWindow(queue: ids, currentIndex: 2)
        #expect(safeLater)
        ready = await preparer.readyTrackIDs
        #expect(!ready.contains(ids[0]))
        #expect(!ready.contains(ids[1]))
        #expect(ready.contains(ids[2]))
        #expect(ready.contains(ids[3]))
    }

    /// An unfetchable next track must make the window report unsafe rather than claim readiness.
    @Test func windowReportsUnsafeWhenTheNextTrackCannotBePrepared() async throws {
        let urls = try Self.makeContinuousToneParts(count: 1)
        defer { Self.cleanUp(urls) }
        let ids = [urls[0].lastPathComponent, "missing-track"]
        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(albumFiles: urls))

        let safe = await preparer.advanceWindow(queue: ids, currentIndex: 0)

        #expect(!safe)
        let ready = await preparer.readyTrackIDs
        #expect(ready == [ids[0]])
    }

    @Test func resetDropsEveryPreparedTrack() async throws {
        let urls = try Self.makeContinuousToneParts(count: 2)
        defer { Self.cleanUp(urls) }
        let ids = urls.map(\.lastPathComponent)
        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(albumFiles: urls))
        _ = await preparer.advanceWindow(queue: ids, currentIndex: 0)

        await preparer.reset()

        let ready = await preparer.readyTrackIDs
        #expect(ready.isEmpty)
    }

    // MARK: - End-to-end frame continuity through the real pipeline

    @Test func pipelinePreparedTracksRenderFrameContinuous() async throws {
        let urls = try Self.makeContinuousToneParts(count: 4)
        defer { Self.cleanUp(urls) }
        let ids = urls.map(\.lastPathComponent)
        let renderFormat = try AVAudioFile(forReading: urls[0]).processingFormat
        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(albumFiles: urls),
                                            renderSampleRate: renderFormat.sampleRate)

        // Prepare through the rolling window, exactly as playback would.
        var tracks: [GaplessPreparedTrack] = []
        for (index, id) in ids.enumerated() {
            _ = await preparer.advanceWindow(queue: ids, currentIndex: index)
            tracks.append(try await preparer.preparedTrack(id))
        }

        let engine = PersistentGaplessEngine(renderFormat: renderFormat)
        try engine.schedule(tracks: tracks)
        let rendered = try engine.renderOfflineChannel0()

        // 1. Frame accounting matches the audio actually scheduled.
        #expect(engine.scheduler.totalFrames == AVAudioFramePosition(4 * Self.partFrames))
        #expect(abs(rendered.count - 4 * Self.partFrames) <= 1)

        // 2. The source is ONE continuous sine, so any inserted/dropped frame at a join is a phase
        //    jump — a sample-to-sample delta far above the smooth in-cycle delta.
        let start = rendered.firstIndex { abs($0) > Self.amp * 0.02 } ?? 0
        let tone = Array(rendered[start...])
        var inCycle: Float = 0
        for i in 5_000..<6_000 where i + 1 < tone.count {
            inCycle = max(inCycle, abs(tone[i + 1] - tone[i]))
        }
        var worst: Float = 0
        for i in 0..<(tone.count - 1) { worst = max(worst, abs(tone[i + 1] - tone[i])) }
        #expect(inCycle > 0)
        #expect(worst <= inCycle * 3.0)

        // 3. Each boundary specifically is indistinguishable from an in-track step.
        for boundary in 1..<4 {
            let idx = boundary * Self.partFrames
            guard idx < tone.count else { continue }
            #expect(abs(tone[idx] - tone[idx - 1]) <= inCycle * 3.0)
        }
    }

    /// The scheduler's segment map is what flips metadata/scrobble at the audible boundary, so it
    /// must reflect the *trimmed* frame counts the engine actually scheduled.
    @Test func schedulerBoundariesFollowPreparedRenderFrames() async throws {
        let urls = try Self.makeContinuousToneParts(count: 3)
        defer { Self.cleanUp(urls) }
        let ids = urls.map(\.lastPathComponent)
        let renderFormat = try AVAudioFile(forReading: urls[0]).processingFormat
        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(albumFiles: urls),
                                            renderSampleRate: renderFormat.sampleRate)
        var tracks: [GaplessPreparedTrack] = []
        for id in ids { tracks.append(try await preparer.preparedTrack(id)) }

        let engine = PersistentGaplessEngine(renderFormat: renderFormat)
        try engine.schedule(tracks: tracks)

        let frames = AVAudioFramePosition(Self.partFrames)
        #expect(engine.scheduler.segment(atRenderFrame: frames - 1)?.id == ids[0])
        #expect(engine.scheduler.segment(atRenderFrame: frames)?.id == ids[1])
        #expect(engine.scheduler.segment(atRenderFrame: frames * 2)?.id == ids[2])
    }

    // MARK: - Fixtures

    /// `count` parts of ONE continuous sine, each exactly `frames` long. The phase index runs
    /// unbroken across parts, so the ideal concatenation is a pure continuous sine and any
    /// scheduling gap or duplication shows up as a discontinuity.
    static func makeContinuousToneParts(count: Int, sampleRate: Double = sampleRate,
                                        frames: Int = partFrames) throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gpipe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for part in 0..<count {
            var samples = [Int16](repeating: 0, count: frames)
            for i in 0..<frames {
                let n = part * frames + i
                let v = amp * Float(sin(2.0 * .pi * freq * Double(n) / sampleRate))
                samples[i] = Int16((max(-1, min(1, v)) * 32767).rounded())
            }
            let url = dir.appendingPathComponent("part\(part + 1).wav")
            try writeWav(url: url, samples: samples, sampleRate: sampleRate)
            urls.append(url)
        }
        return urls
    }

    static func cleanUp(_ urls: [URL]) {
        guard let dir = urls.first?.deletingLastPathComponent() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Manual RIFF writer — `AVAudioFile` would packet-quantize and break the sample-exact split.
    static func writeWav(url: URL, samples: [Int16], sampleRate: Double) throws {
        let rate = UInt32(sampleRate)
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
