import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Per-format frame-continuity evidence for the Checkpoint 3 streaming pipeline, run against **real
/// encoded albums** through the **production** types (`GaplessTrackPreparer` -> `GaplessTrimPolicy`
/// -> `PersistentGaplessEngine`) rather than a bespoke test rig.
///
/// Each album is one continuous tone split into 4 sample-exact 10 s parts, with every part encoded
/// independently — the way a server stores tracks and the way Navidrome transcodes them, so codec
/// priming and padding land on every join. Regenerate with
/// `spike/gapless-formats/make-test-albums.sh`.
///
/// These tests are skipped when the media isn't present (CI machines), so they never fail for the
/// wrong reason. The synthetic proofs in `GaplessPipelineOfflineTests` are self-contained and always
/// run.
struct GaplessRealAlbumTests {
    static let partSeconds = 10.0

    /// The test media lives on the *host* Mac, not in the app sandbox. A simulator process can read
    /// it, but has to be told where it is: `SIMULATOR_HOST_HOME` is the host user's home directory.
    /// Falls back to a path that cannot exist, so an unlocatable media root skips these tests rather
    /// than failing them.
    static let mediaRoot: URL = {
        let environment = ProcessInfo.processInfo.environment
        if let explicit = environment["VIBRDROME_TEST_MEDIA"] {
            return URL(fileURLWithPath: explicit)
        }
        if let hostHome = environment["SIMULATOR_HOST_HOME"] {
            return URL(fileURLWithPath: hostHome).appendingPathComponent("vibrdrome-test-media")
        }
        #if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("vibrdrome-test-media")
        #else
        return URL(fileURLWithPath: "/vibrdrome-test-media-unavailable")
        #endif
    }()

    struct Album: CustomStringConvertible, Sendable {
        let directory: String
        /// How this album's tracks are expected to be trimmed before scheduling.
        let expectedTrimReason: GaplessTrim.Reason
        /// Whether the joins are expected to be frame-exact after trimming.
        let expectsFrameExact: Bool
        var description: String { directory }
    }

    /// One entry per delivery path Vibrdrome plays. The transcoded-MP3 entry is the known limit of
    /// the format, pinned by a test rather than described in a comment.
    static let albums: [Album] = [
        Album(directory: "Gapless 4-Track Test", expectedTrimReason: .wholeFile, expectsFrameExact: true),
        Album(directory: "Gapless 4-Track ALAC", expectedTrimReason: .wholeFile, expectsFrameExact: true),
        Album(directory: "Gapless 4-Track AAC", expectedTrimReason: .wholeFile, expectsFrameExact: true),
        Album(directory: "Gapless 4-Track Opus", expectedTrimReason: .wholeFile, expectsFrameExact: true),
        Album(directory: "Gapless 4-Track MP3", expectedTrimReason: .lameGaplessHeader, expectsFrameExact: true)
    ]

    static var mediaAvailable: Bool {
        albums.allSatisfy { FileManager.default.fileExists(atPath: mediaRoot.appendingPathComponent($0.directory).path) }
    }

    // MARK: - Per-format continuity through the production pipeline

    @Test(.enabled(if: mediaAvailable), arguments: albums)
    func realAlbumJoinsAreFrameContinuous(album: Album) async throws {
        let urls = try Self.trackURLs(in: album.directory)
        #expect(urls.count == 4)

        let renderFormat = try AVAudioFile(forReading: urls[0]).processingFormat
        let ids = urls.map(\.lastPathComponent)
        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(albumFiles: urls),
                                            renderSampleRate: renderFormat.sampleRate)

        // Drive the rolling window exactly as playback would, then schedule what it prepared.
        var tracks: [GaplessPreparedTrack] = []
        for (index, id) in ids.enumerated() {
            let safe = await preparer.advanceWindow(queue: ids, currentIndex: index)
            #expect(safe, "window was not boundary-safe at index \(index) for \(album)")
            tracks.append(try await preparer.preparedTrack(id))
        }

        // Every track is trimmed the way this format requires, and lands on the true source length.
        // Opus decodes at 48 kHz, so the expected count is computed at the file's own rate.
        let expectedFrames = AVAudioFramePosition((Self.partSeconds * renderFormat.sampleRate).rounded())
        for track in tracks {
            #expect(track.trim.reason == album.expectedTrimReason, "\(album): unexpected trim for \(track.trackID)")
            if album.expectsFrameExact {
                #expect(track.renderFrames == expectedFrames,
                        "\(album): \(track.trackID) scheduled \(track.renderFrames) frames, expected \(expectedFrames)")
            }
        }

        let engine = PersistentGaplessEngine(renderFormat: renderFormat)
        try engine.schedule(tracks: tracks)
        #expect(engine.scheduler.totalFrames == expectedFrames * 4)

        let rendered = try engine.renderOfflineChannel0()
        let measurement = Self.measureContinuity(rendered, partFrames: Int(expectedFrames), parts: 4)

        #expect(abs(rendered.count - Int(expectedFrames) * 4) <= 1,
                "\(album): rendered \(rendered.count) frames, expected \(expectedFrames * 4)")
        #expect(measurement.inCycleDelta > 0)
        // A gap, duplicate, or dropped frame at a join is a phase jump in a continuous tone — a
        // sample-to-sample delta far above the smooth in-cycle delta.
        #expect(measurement.worstDelta <= measurement.inCycleDelta * 3.0,
                "\(album): worst delta \(measurement.worstDelta) vs in-cycle \(measurement.inCycleDelta)")
        for (index, delta) in measurement.boundaryDeltas.enumerated() {
            #expect(delta <= measurement.inCycleDelta * 3.0,
                    "\(album): boundary \(index + 1)->\(index + 2) delta \(delta)")
        }
    }

    // MARK: - The one format that cannot be made exact

    /// A live server-side transcode streams from a non-seekable pipe, so the MP3 encoder never fills
    /// in its Xing/LAME gapless header and no exact trim exists. The engine must **report** that
    /// rather than silently ship a gap, so this pins the reported reason and the resulting error.
    @Test(.enabled(if: FileManager.default.fileExists(
        atPath: mediaRoot.appendingPathComponent("Gapless 4-Track Transcoded MP3").path)))
    func transcodedMP3WithoutGaplessHeaderIsReportedNotHidden() async throws {
        let urls = try Self.trackURLs(in: "Gapless 4-Track Transcoded MP3")
        let renderFormat = try AVAudioFile(forReading: urls[0]).processingFormat
        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(albumFiles: urls),
                                            renderSampleRate: renderFormat.sampleRate)

        let track = try await preparer.preparedTrack(urls[0].lastPathComponent)

        #expect(track.trim.reason == .mp3WithoutGaplessHeader)
        // The codec's inserted frames survive into the schedule — that is the cost being reported.
        let expectedFrames = AVAudioFramePosition((Self.partSeconds * renderFormat.sampleRate).rounded())
        #expect(track.renderFrames > expectedFrames)
    }

    // MARK: - Helpers

    static func trackURLs(in directory: String) throws -> [URL] {
        let audioExtensions: Set<String> = ["flac", "m4a", "mp3", "wav", "opus"]
        let dir = mediaRoot.appendingPathComponent(directory)
        return try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    struct Continuity {
        let inCycleDelta: Float
        let worstDelta: Float
        let boundaryDeltas: [Float]
    }

    /// Smooth in-track step size vs the worst step anywhere, plus the step at each join.
    static func measureContinuity(_ rendered: [Float], partFrames: Int, parts: Int) -> Continuity {
        // Trim constant startup latency so frame indices line up with the source timeline.
        var peak: Float = 0
        for value in rendered.prefix(partFrames) { peak = max(peak, abs(value)) }
        let start = rendered.firstIndex { abs($0) > peak * 0.05 } ?? 0
        let tone = Array(rendered[start...])

        var inCycle: Float = 0
        for i in 5_000..<6_000 where i + 1 < tone.count {
            inCycle = max(inCycle, abs(tone[i + 1] - tone[i]))
        }
        var worst: Float = 0
        for i in 0..<max(0, tone.count - 1) { worst = max(worst, abs(tone[i + 1] - tone[i])) }

        var boundaries: [Float] = []
        for boundary in 1..<parts {
            let idx = boundary * partFrames
            guard idx > 0, idx < tone.count else { continue }
            boundaries.append(abs(tone[idx] - tone[idx - 1]))
        }
        return Continuity(inCycleDelta: inCycle, worstDelta: worst, boundaryDeltas: boundaries)
    }
}
