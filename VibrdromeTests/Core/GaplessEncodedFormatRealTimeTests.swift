import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Encoded formats played for real, through the production `GaplessPlaybackController`, with the
/// audible order recovered from captured output.
///
/// Each album's parts are *distinct* non-harmonic tones, so the captured audio proves which track
/// was heard and in what order — something the continuous-tone albums cannot show, since every part
/// of those sounds identical. Continuity of a *join* is proven separately (offline, frame-exact);
/// what this file adds is that real decoding, real trimming and real scheduling put the right audio
/// out of the speaker in the right order.
///
/// Skipped when the media isn't present, so a machine without fixtures never fails for the wrong
/// reason. Regenerate with `spike/gapless-formats/make-identity-albums.sh`.
/// Fixture data for the encoded-format runs.
///
/// Deliberately **nonisolated**: Swift Testing evaluates `.enabled(if:)` traits and `arguments:`
/// collections outside any actor, so main-actor-isolated statics cannot be used there.
enum GaplessFormatFixtures {
    static let sampleRate = 44_100.0
    /// Distinct, non-harmonic: no ratio near an integer, so one part's harmonic cannot be read as
    /// another part.
    static let tones: [Double] = [233, 379, 611, 977]

    static let mediaRoot: URL = {
        let environment = ProcessInfo.processInfo.environment
        if let explicit = environment["VIBRDROME_TEST_MEDIA"] { return URL(fileURLWithPath: explicit) }
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

    struct Album: Sendable, CustomStringConvertible {
        let directory: String
        /// How preparation is expected to classify these files.
        let expectedTrim: GaplessTrim.Reason
        /// Whether this delivery path can be presented as gapless.
        let gaplessCapable: Bool
        var description: String { directory }
    }

    static let albums: [Album] = [
        Album(directory: "Identity FLAC", expectedTrim: .wholeFile, gaplessCapable: true),
        Album(directory: "Identity ALAC", expectedTrim: .wholeFile, gaplessCapable: true),
        Album(directory: "Identity AAC", expectedTrim: .wholeFile, gaplessCapable: true),
        Album(directory: "Identity Opus", expectedTrim: .wholeFile, gaplessCapable: true),
        Album(directory: "Identity MP3 CBR", expectedTrim: .lameGaplessHeader, gaplessCapable: true),
        Album(directory: "Identity MP3 VBR", expectedTrim: .lameGaplessHeader, gaplessCapable: true),
        Album(directory: "Identity MP3 Mono", expectedTrim: .lameGaplessHeader, gaplessCapable: true),
        Album(directory: "Identity MP3 MPEG2", expectedTrim: .lameGaplessHeader, gaplessCapable: true)
    ]

    static func available(_ directory: String) -> Bool {
        FileManager.default.fileExists(atPath: mediaRoot.appendingPathComponent(directory).path)
    }

    static var mediaAvailable: Bool { albums.allSatisfy { available($0.directory) } }

    static func trackURLs(in directory: String) throws -> [URL] {
        let extensions: Set<String> = ["flac", "m4a", "mp3", "opus", "wav"]
        return try FileManager.default
            .contentsOfDirectory(at: mediaRoot.appendingPathComponent(directory),
                                 includingPropertiesForKeys: nil)
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

@MainActor
struct GaplessEncodedFormatRealTimeTests {
    typealias Album = GaplessFormatFixtures.Album
    static let sampleRate = GaplessFormatFixtures.sampleRate
    static let tones = GaplessFormatFixtures.tones
    static func trackURLs(in directory: String) throws -> [URL] {
        try GaplessFormatFixtures.trackURLs(in: directory)
    }

    /// Wire an album through the real controller with output capture attached.
    static func makeRig(album directory: String,
                        repeatMode: RepeatMode = .off) throws -> (rig: Rig, urls: [URL]) {
        let urls = try trackURLs(in: directory)
        var files: [String: URL] = [:]
        var songIDs: [String] = []
        for url in urls {
            let songID = url.lastPathComponent
            files[songID] = url
            songIDs.append(songID)
        }

        let session = GaplessPlaybackSession(sampleRate: sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = 0.4 }
        session.setRepeatMode(repeatMode)

        let backend = GaplessRealTimeBackend()
        #if os(iOS)
        backend.activateAudioSession = {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default)
            try audio.setActive(true)
        }
        backend.deactivateAudioSession = { try? AVAudioSession.sharedInstance().setActive(false) }
        #endif
        // The persistent visualizer feed is installed for every format run, so the format proof also
        // exercises the tap being present across boundaries.
        backend.engine.installVisualizerFeed()

        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(filesByTrackID: files),
                                            renderSampleRate: sampleRate)
        let controller = GaplessPlaybackController(session: session, backend: backend,
                                                   preparer: preparer)
        let rig = Rig(controller: controller,
                      capture: GaplessRealTimeCapture(engine: backend.engine), songIDs: songIDs)
        return (rig, urls)
    }

    @MainActor
    struct Rig {
        let controller: GaplessPlaybackController
        let capture: GaplessRealTimeCapture
        let songIDs: [String]

        func cleanUp() {
            capture.stop()
            controller.backend.engine.uninstallVisualizerFeed()
            controller.stop()
        }

        func heard() -> [Double] {
            capture.heardSequence(frequencies: GaplessEncodedFormatRealTimeTests.tones,
                                  sampleRate: GaplessEncodedFormatRealTimeTests.sampleRate)
        }
    }

    @discardableResult
    static func run(_ rig: Rig, until what: String, timeout: TimeInterval = 60,
                    _ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await rig.controller.tick()
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(4))
        }
        Issue.record("timed out waiting for \(what)")
        return false
    }

    // MARK: - Trim classification per format

    /// Preparation must classify each format correctly *before* any audio plays — the trim decides
    /// the scheduled range, so a wrong classification is a wrong segment.
    @Test(.enabled(if: GaplessFormatFixtures.mediaAvailable), arguments: GaplessFormatFixtures.albums)
    func formatIsClassifiedCorrectlyByPreparation(album: Album) async throws {
        let urls = try Self.trackURLs(in: album.directory)
        #expect(urls.count == 4, "\(album): expected 4 parts")

        for url in urls {
            let prepared = try GaplessTrackPreparer.describe(trackID: url.lastPathComponent,
                                                             fileURL: url,
                                                             renderSampleRate: Self.sampleRate)
            #expect(prepared.trim.reason == album.expectedTrim,
                    "\(album)/\(url.lastPathComponent): \(prepared.trim.reason)")
            #expect(prepared.trim.frameCount > 0)
            #expect(prepared.renderFrames > 0)
        }
    }

    /// Raw trim diagnostics for a representative trimmed MP3 — the parsed values, the validation
    /// outcome and the selected range, all visible rather than inferred.
    @Test(.enabled(if: GaplessFormatFixtures.available("Identity MP3 CBR")))
    func trimmedMP3ExposesItsRawDiagnostics() throws {
        let url = try Self.trackURLs(in: "Identity MP3 CBR")[0]
        let decoded = try AVAudioFile(forReading: url).length
        let diagnostics = GaplessTrimPolicy.diagnostics(forFileAt: url, decodedLength: decoded)

        #expect(diagnostics.validation == .accepted)
        #expect(diagnostics.rawEncoderDelay != nil)
        #expect(diagnostics.rawPadding != nil)
        #expect(diagnostics.selectedStartFrame == AVAudioFramePosition(diagnostics.rawEncoderDelay ?? -1))
        // The scheduled range excludes both encoder delay and end padding.
        let expected = decoded - AVAudioFramePosition(diagnostics.rawEncoderDelay ?? 0)
            - AVAudioFramePosition(diagnostics.rawPadding ?? 0)
        #expect(diagnostics.selectedFrameCount == AVAudioFrameCount(expected))
    }

    // MARK: - Real-time audible order per format

    /// Play the whole album for real and confirm the captured audio is the right tracks in the right
    /// order, with the graph never rebuilt.
    @Test(.enabled(if: GaplessFormatFixtures.mediaAvailable), arguments: GaplessFormatFixtures.albums)
    func formatPlaysInOrderInRealTime(album: Album) async throws {
        let (rig, _) = try Self.makeRig(album: album.directory)
        defer { rig.cleanUp() }
        let playerBefore = ObjectIdentifier(rig.controller.backend.engine.player)
        let eqBefore = ObjectIdentifier(rig.controller.backend.engine.eq)

        rig.capture.start()
        try await rig.controller.play()
        await Self.run(rig, until: "four tones heard for \(album)") {
            rig.heard().count >= 4
        }
        try await Task.sleep(for: .milliseconds(150))

        let heard = Array(rig.heard().prefix(4))
        #expect(heard == Self.tones, "\(album) heard \(heard)")
        // One play instance per actual play, no duplicates.
        let instances = rig.controller.observedBoundaries.prefix(4).map(\.playInstance)
        #expect(Set(instances).count == 4, "\(album)")
        // The graph is never rebuilt for any format.
        #expect(ObjectIdentifier(rig.controller.backend.engine.player) == playerBefore)
        #expect(ObjectIdentifier(rig.controller.backend.engine.eq) == eqBefore)
        #expect(rig.controller.backend.engine.engine.isRunning)
        // The visualizer tap survived every boundary.
        #expect(rig.controller.backend.engine.visualizerFeed.isInstalled)
        // Local files must never miss a deadline.
        #expect(rig.controller.deadlineMisses.isEmpty, "\(album)")
    }

    /// 25+ automatic transitions per format, under Repeat All.
    @Test(.enabled(if: GaplessFormatFixtures.mediaAvailable), arguments: GaplessFormatFixtures.albums)
    func formatSurvivesTwentyFiveTransitions(album: Album) async throws {
        let (rig, _) = try Self.makeRig(album: album.directory, repeatMode: .all)
        defer { rig.cleanUp() }
        let playerBefore = ObjectIdentifier(rig.controller.backend.engine.player)

        try await rig.controller.play()
        await Self.run(rig, until: "25 transitions for \(album)", timeout: 90) {
            rig.controller.observedBoundaries.count >= 26
        }

        let boundaries = rig.controller.observedBoundaries
        #expect(boundaries.count >= 26, "\(album): \(boundaries.count) boundaries")
        // Every play is its own instance — no duplicates, none missing.
        #expect(Set(boundaries.map(\.playInstance)).count == boundaries.count, "\(album)")
        // Repeat All cycles the queue in order.
        let expectedOrder = (0..<boundaries.count).map { rig.songIDs[$0 % rig.songIDs.count] }
        #expect(boundaries.map(\.songID) == expectedOrder, "\(album)")
        // No engine restart or node replacement across 25 transitions.
        #expect(ObjectIdentifier(rig.controller.backend.engine.player) == playerBefore)
        #expect(rig.controller.backend.engine.engine.isRunning)
        #expect(rig.controller.deadlineMisses.isEmpty, "\(album)")
        // Advancing never bumps the queue generation.
        #expect(rig.controller.session.queue.generation == 1, "\(album)")
    }

    /// Seek and Play Next on a real encoded format, verified by captured audio.
    @Test(.enabled(if: GaplessFormatFixtures.mediaAvailable), arguments: GaplessFormatFixtures.albums)
    func formatSupportsSeekAndPlayNext(album: Album) async throws {
        let (rig, _) = try Self.makeRig(album: album.directory)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()
        await Self.run(rig, until: "first tone heard for \(album)") { !rig.heard().isEmpty }

        // Seek inside the trimmed range — must stay within the source, never expose padding.
        try await rig.controller.seek(toSeconds: 0.15)
        #expect(rig.controller.session.queue.currentIndex == 0, "\(album)")

        // Play Next puts the last track immediately after the current one.
        try await rig.controller.playNext(songID: rig.songIDs[3])
        await Self.run(rig, until: "the inserted track for \(album)", timeout: 45) {
            rig.heard().count >= 2
        }
        try await Task.sleep(for: .milliseconds(150))

        let heard = rig.heard()
        #expect(heard.first == Self.tones[0], "\(album) heard \(heard)")
        #expect(heard.contains(Self.tones[3]), "\(album) heard \(heard)")
        #expect(rig.controller.backend.engine.engine.isRunning)
    }

    // MARK: - Opus specifics

    /// Opus decodes at 48 kHz into a 44.1 kHz graph, so it exercises the sample-rate conversion path.
    @Test(.enabled(if: GaplessFormatFixtures.available("Identity Opus")))
    func opusDecodesAt48kHzAndConvertsForTheGraph() throws {
        let urls = try Self.trackURLs(in: "Identity Opus")
        for url in urls {
            let file = try AVAudioFile(forReading: url)
            #expect(file.processingFormat.sampleRate == 48_000)
            let prepared = try GaplessTrackPreparer.describe(trackID: url.lastPathComponent,
                                                             fileURL: url,
                                                             renderSampleRate: Self.sampleRate)
            // Source frames are at 48 kHz; render frames are the converted count, so boundary
            // accounting stays exact rather than drifting by the rate ratio.
            #expect(prepared.sourceSampleRate == 48_000)
            #expect(!prepared.matchesRenderRate)
            let ratio = Double(prepared.renderFrames) / Double(prepared.trim.frameCount)
            #expect(abs(ratio - 44_100.0 / 48_000.0) < 0.001)
        }
    }

    // MARK: - MP3 without trustworthy metadata

    /// The one delivery path that cannot be guaranteed gapless. It must still play correctly, must
    /// not be trimmed by guesswork, and must be visible as unsupported.
    @Test(.enabled(if: GaplessFormatFixtures.available("Identity MP3 NoMetadata")))
    func mp3WithoutMetadataPlaysButIsNotClaimedGapless() async throws {
        let urls = try Self.trackURLs(in: "Identity MP3 NoMetadata")
        for url in urls {
            let decoded = try AVAudioFile(forReading: url).length
            let diagnostics = GaplessTrimPolicy.diagnostics(forFileAt: url, decodedLength: decoded)
            // No header, so no delay/padding values and no guessed constant.
            #expect(diagnostics.validation == .metadataAbsent)
            #expect(diagnostics.rawEncoderDelay == nil)
            #expect(diagnostics.rawPadding == nil)
            // The whole file is scheduled — never a fabricated 576/792 range.
            #expect(diagnostics.selectedStartFrame == 0)
            #expect(diagnostics.selectedFrameCount == AVAudioFrameCount(decoded))

            let capability = GaplessCapability.evaluate(trimReason: .mp3WithoutGaplessMetadata)
            #expect(!capability.isGaplessCapable)
            #expect(capability.reason == .unsupportedSource)
        }

        // It still plays, in the right order, without crashing.
        let (rig, _) = try Self.makeRig(album: "Identity MP3 NoMetadata")
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()
        await Self.run(rig, until: "unsupported MP3 to play through", timeout: 45) {
            rig.heard().count >= 4
        }

        let heard = Array(rig.heard().prefix(4))
        #expect(heard == Self.tones, "heard \(heard)")
        #expect(rig.controller.session.queue.items.allSatisfy { $0.state != .failed })
    }

    // MARK: - Source-path equivalence

    /// The same audio delivered as a downloaded file, a cache hit, or a fresh fetch must produce the
    /// same trim decision and the same scheduled range — the source path must not change semantics.
    @Test(.enabled(if: GaplessFormatFixtures.available("Identity FLAC")))
    func sourcePathDoesNotChangeTrimSemantics() async throws {
        let original = try Self.trackURLs(in: "Identity FLAC")[0]

        // "Downloaded" — the file where the download layer put it.
        let downloaded = try GaplessTrackPreparer.describe(trackID: "downloaded",
                                                           fileURL: original,
                                                           renderSampleRate: Self.sampleRate)
        // "Cache hit" — the same bytes under a gapless-cache name.
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let cached = cacheDirectory.appendingPathComponent("cached.flac")
        try FileManager.default.copyItem(at: original, to: cached)
        let fromCache = try GaplessTrackPreparer.describe(trackID: "cached", fileURL: cached,
                                                          renderSampleRate: Self.sampleRate)

        #expect(downloaded.trim.reason == fromCache.trim.reason)
        #expect(downloaded.trim.startFrame == fromCache.trim.startFrame)
        #expect(downloaded.trim.frameCount == fromCache.trim.frameCount)
        #expect(downloaded.renderFrames == fromCache.renderFrames)

        // The streaming provider prefers an existing local file over fetching, so a cache hit never
        // re-downloads and never re-decides the trim.
        let provider = GaplessStreamingFileProvider(
            cacheDirectory: cacheDirectory,
            existingLocalFile: { _ in original },
            remoteURL: { _ in nil })
        let resolved = try await provider.localFile(forTrack: "anything")
        #expect(resolved == original)
    }
}
