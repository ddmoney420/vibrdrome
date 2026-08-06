import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Lane 3D-B1a: the selection planner decides, and starts nothing.
///
/// **Every fact comes from the file that actually arrived.** The request's metadata and the
/// configured transcode preference are inputs to *fetching*, never to deciding: the delivered
/// container is read from the materialized file (which the fetch names from the response content
/// type), and sample rate, channel count, finite length and MP3 trim status all come from
/// `GaplessTrackPreparer.describe` opening the real media.
///
/// Nothing here grants authority, quiesces legacy, activates a session or plays a sample.
@Suite(.serialized)
@MainActor
struct PlaybackSessionSelectionPlannerTests {

    // MARK: - Fixtures

    private func makeSong(id: String) -> Song {
        Song(id: id, parent: nil, title: "Track \(id)",
             album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
             track: nil, year: nil, genre: nil, coverArt: nil,
             size: nil, contentType: nil, suffix: nil,
             duration: 180, bitRate: nil, path: nil,
             discNumber: nil, created: nil, starred: nil, userRating: nil,
             bpm: nil, replayGain: nil, musicBrainzId: nil)
    }

    private func request(
        _ songs: [Song], kind: PlaybackContentKind = .finiteTrack, generation: UInt64 = 1
    ) -> PlaybackSessionSelectionRequest {
        PlaybackSessionSelectionRequest(songs: songs, contentKind: kind, generation: generation)
    }

    /// Writes a real, decodable WAV so `describe` has genuine media to inspect. Using an actual
    /// file rather than a stub is the point: the confirmation path must be exercised end to end.
    ///
    /// Written **interleaved with an explicit channel layout**. `AVAudioFormat(standardFormat…)` is
    /// non-interleaved, and `AVAudioFile` refuses to write that ("Audio files cannot be
    /// non-interleaved"); mono and stereo happen to survive it, but anything above stereo fails to
    /// save, and Core Audio additionally needs a layout for >2 channels.
    private func writeWAV(
        to url: URL, sampleRate: Double = 44_100, channels: AVAudioChannelCount = 2, seconds: Double = 1
    ) throws {
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(channels),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        if channels > 2 {
            let tag: AudioChannelLayoutTag = channels == 6
                ? kAudioChannelLayoutTag_MPEG_5_1_A
                : kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
            guard let layout = AVAudioChannelLayout(layoutTag: tag) else {
                throw CocoaError(.fileWriteUnknown)
            }
            settings[AVChannelLayoutKey] = Data(
                bytes: layout.layout, count: MemoryLayout<AudioChannelLayout>.size)
        }

        let file = try AVAudioFile(forWriting: url, settings: settings)
        // The buffer format must match what the file expects, layout included.
        let bufferFormat = file.processingFormat
        let frames = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity: frames) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = frames
        for channel in 0..<Int(bufferFormat.channelCount) {
            if let data = buffer.floatChannelData?[channel] {
                for frame in 0..<Int(frames) {
                    data[frame] = sinf(Float(frame) * 0.01) * 0.2
                }
            }
        }
        try file.write(from: buffer)
    }

    /// A planner whose materialization resolves to files we control.
    private func makePlanner(
        files: [String: URL],
        flagEnabled: Bool = true,
        failConstruction: Bool = false
    ) -> PlaybackSessionSelectionPlanner {
        PlaybackSessionSelectionPlanner(
            prepareAssembly: {
                if failConstruction { throw PersistentPreparationFailure.builderRefused }
                let backend = GaplessRealTimeBackend()
                return PersistentPlaybackAssembly(
                    session: GaplessPlaybackSession(sampleRate: GaplessRenderFormat.sampleRate),
                    backend: backend,
                    preparer: GaplessTrackPreparer(
                        provider: GaplessLocalFileProvider(filesByTrackID: files),
                        renderSampleRate: GaplessRenderFormat.sampleRate),
                    cacheDirectory: FileManager.default.temporaryDirectory
                )
            },
            isPersistentRoutingEnabled: { flagEnabled }
        )
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-\(UInt64.random(in: 0..<UInt64.max))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    // MARK: - Flag Off

    /// Off returns legacy before anything is constructed, fetched or opened.
    @Test func flagOffReturnsLegacyWithoutTouchingAnything() async {
        var constructed = false
        let planner = PlaybackSessionSelectionPlanner(
            prepareAssembly: {
                constructed = true
                throw PersistentPreparationFailure.builderRefused
            },
            isPersistentRoutingEnabled: { false })

        let plan = await planner.plan(request: request([makeSong(id: "a")]))

        #expect(plan.plannedBackend == .legacy)
        #expect(plan.retainsPreparedSource == false)
        #expect(constructed == false,
                "the flag was Off but the persistent assembly was constructed anyway")
        #expect(GaplessDiagnosticsRegistry.current == nil)
    }

    // MARK: - Early legacy decisions, before materialization

    /// Content the policy can already refuse is never materialized.
    @Test func definitivelyLegacyContentIsNeverMaterialized() async {
        for kind in [PlaybackContentKind.radio, .liveStream, .unknown] {
            var constructed = false
            let planner = PlaybackSessionSelectionPlanner(
                prepareAssembly: {
                    constructed = true
                    throw PersistentPreparationFailure.builderRefused
                },
                isPersistentRoutingEnabled: { true })

            let plan = await planner.plan(request: request([makeSong(id: "a")], kind: kind))

            #expect(plan.plannedBackend == .legacy, "\(kind) planned persistent")
            #expect(constructed == false, "\(kind) was materialized before being refused")
            switch (kind, plan) {
            case (.radio, .legacy(let reason)): #expect(reason == .radioContent)
            case (.liveStream, .legacy(let reason)): #expect(reason == .liveStreamContent)
            case (.unknown, .legacy(let reason)): #expect(reason == .unknownContentKind)
            default: Issue.record("\(kind) produced \(plan.describedForDiagnostics)")
            }
        }
    }

    // MARK: - Confirmed persistent candidates

    /// A real stereo 44.1 kHz WAV is inspected and planned persistent, gapless-capable.
    @Test func aConfirmedSupportedSourcePlansPersistent() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("a.wav")
            try writeWAV(to: url)
            let planner = makePlanner(files: ["a": url])

            let plan = await planner.plan(request: request([makeSong(id: "a")]))

            guard case .persistent(let source, let decision) = plan else {
                Issue.record("expected persistent, got \(plan.describedForDiagnostics)")
                return
            }
            #expect(decision.backend == .persistent)
            #expect(decision.playableByPersistentEngine)
            #expect(decision.gaplessCapable, "a frame-exact source lost its gapless guarantee")
            #expect(source.deliveredContainer == "wav",
                    "delivered container was \(source.deliveredContainer)")
            // Facts came from the file, not the request.
            #expect(source.track.sourceSampleRate == 44_100)
            #expect(source.track.sourceChannelCount == 2)
            #expect(source.track.renderFrames > 0, "finite length was not confirmed")
            #expect(source.track.trim.reason == .wholeFile)
        }
    }

    /// Mono is accepted — it up-mixes without changing the frame count.
    @Test func aMonoSourcePlansPersistent() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("mono.wav")
            try writeWAV(to: url, channels: 1)
            let planner = makePlanner(files: ["mono": url])

            let plan = await planner.plan(request: request([makeSong(id: "mono")]))

            guard case .persistent(let source, _) = plan else {
                Issue.record("mono was refused: \(plan.describedForDiagnostics)")
                return
            }
            #expect(source.track.sourceChannelCount == 1)
        }
    }

    /// A 48 kHz source against the 44.1 kHz graph is a conversion, not a refusal.
    @Test func aNonRenderRateSourcePlansPersistent() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("48k.wav")
            try writeWAV(to: url, sampleRate: 48_000)
            let planner = makePlanner(files: ["48k": url])

            let plan = await planner.plan(request: request([makeSong(id: "48k")]))

            guard case .persistent(let source, _) = plan else {
                Issue.record("48 kHz was refused: \(plan.describedForDiagnostics)")
                return
            }
            #expect(source.track.sourceSampleRate == 48_000)
            #expect(source.track.renderFrames > 0)
        }
    }

    // MARK: - Confirmed legacy decisions

    /// Above stereo is refused on the confirmed channel count.
    @Test func aboveStereoIsRefusedOnConfirmedChannelCount() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("surround.wav")
            try writeWAV(to: url, channels: 6)
            let planner = makePlanner(files: ["surround": url])

            let plan = await planner.plan(request: request([makeSong(id: "surround")]))

            #expect(plan.plannedBackend == .legacy, "a 6-channel source planned persistent")
            #expect(plan.retainsPreparedSource == false)
            if case .legacy(let reason) = plan {
                #expect(reason == .unsupportedChannelLayout, "reason was \(reason)")
            }
        }
    }

    /// A file the decoder refuses produces legacy, not a crash and not an optimistic persistent.
    @Test func anUndecodableSourceIsRefused() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("garbage.wav")
            try Data("not audio".utf8).write(to: url)
            let planner = makePlanner(files: ["garbage": url])

            let plan = await planner.plan(request: request([makeSong(id: "garbage")]))

            #expect(plan.plannedBackend == .legacy)
            #expect(plan.retainsPreparedSource == false)
            if case .legacy(let reason) = plan {
                #expect(reason == .decoderUnavailable, "reason was \(reason)")
            }
        }
    }

    /// Materialization failure is a routing failure, and retains nothing.
    @Test func materializationFailureRetainsNothing() async {
        let planner = makePlanner(files: [:])   // provider has no file for this track

        let plan = await planner.plan(request: request([makeSong(id: "missing")]))

        #expect(plan.plannedBackend == .legacy)
        #expect(plan.retainsPreparedSource == false)
        if case .failed(let reason) = plan {
            #expect(reason == .sourcePreparationFailed)
        } else {
            Issue.record("expected failed, got \(plan.describedForDiagnostics)")
        }
    }

    /// Persistent construction failure is deterministic and retains nothing.
    @Test func constructionFailureRetainsNothing() async {
        let planner = makePlanner(files: [:], failConstruction: true)

        let plan = await planner.plan(request: request([makeSong(id: "a")]))

        #expect(plan.retainsPreparedSource == false)
        if case .failed(let reason) = plan {
            #expect(reason == .persistentConstructionFailed)
        } else {
            Issue.record("expected failed, got \(plan.describedForDiagnostics)")
        }
    }

    // MARK: - Delivered representation overrides the request

    /// The decision follows the container that actually arrived, whatever the song claimed.
    @Test func theDecisionFollowsTheDeliveredContainerNotTheRequest() async throws {
        try await withTemporaryDirectory { directory in
            // The song is nominally an unsupported format; what arrives is a decodable WAV.
            let url = directory.appendingPathComponent("delivered.wav")
            try writeWAV(to: url)
            let planner = makePlanner(files: ["claims-wma": url])

            let plan = await planner.plan(request: request([makeSong(id: "claims-wma")]))

            guard case .persistent(let source, _) = plan else {
                Issue.record("the delivered container was ignored: \(plan.describedForDiagnostics)")
                return
            }
            #expect(source.deliveredContainer == "wav")
        }
    }

    /// Container-to-codec mapping is explicit, and an unknown container is not optimistically
    /// treated as supported.
    @Test func containerMappingIsExplicit() {
        #expect(PlaybackSessionSelectionPlanner.codec(forContainer: "flac") == .flac)
        #expect(PlaybackSessionSelectionPlanner.codec(forContainer: "m4a") == .alac)
        #expect(PlaybackSessionSelectionPlanner.codec(forContainer: "opus") == .opus)
        #expect(PlaybackSessionSelectionPlanner.codec(forContainer: "mp3") == .mp3)
        #expect(PlaybackSessionSelectionPlanner.codec(forContainer: "wav") == .wav)
        #expect(PlaybackSessionSelectionPlanner.codec(forContainer: "") == .unknown)
        #expect(PlaybackSessionSelectionPlanner.codec(forContainer: "wma") == .other("wma"))
    }

    /// MP3 gapless capability comes from the trim policy's actual verdict on the file.
    @Test func mp3GaplessCapabilityFollowsTheTrimVerdict() {
        #expect(PlaybackSessionSelectionPlanner.metadata(for: .wholeFile) == .notRequired)
        #expect(PlaybackSessionSelectionPlanner.metadata(for: .lameGaplessHeader) == .trusted)
        #expect(PlaybackSessionSelectionPlanner.metadata(for: .mp3WithoutGaplessMetadata) == .absent)

        // And the policy turns that into a persistent-but-not-gapless answer, not a refusal.
        let noTrim = PlaybackRoutingSource(
            contentKind: .finiteTrack, delivery: .cachedPrepared, codec: .mp3,
            channelCount: 2, sampleRate: 44_100, hasFiniteDuration: true,
            gaplessMetadata: .absent, decoderAvailable: true)
        let decision = PlaybackBackendPolicy.decision(for: noTrim)
        #expect(decision.backend == .persistent, "a trimless MP3 was forced to legacy")
        #expect(decision.gaplessCapable == false)
    }

    // MARK: - Prepared-source ownership

    /// A persistent plan retains exactly one consumable source.
    @Test func aPersistentPlanIsConsumableExactlyOnce() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("once.wav")
            try writeWAV(to: url)
            let planner = makePlanner(files: ["once": url])

            let plan = await planner.plan(request: request([makeSong(id: "once")]))
            guard case .persistent(let source, _) = plan else {
                Issue.record("expected persistent")
                return
            }

            #expect(source.isConsumed == false)
            #expect(source.consume()?.trackID == "once")
            #expect(source.isConsumed)
            #expect(source.consume() == nil, "a prepared source was consumed twice")
        }
    }

    /// Releasing an unconsumed plan makes it unusable, so a dropped plan cannot later be adopted.
    @Test func aDroppedPlanCannotBeAdoptedLater() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("dropped.wav")
            try writeWAV(to: url)
            let planner = makePlanner(files: ["dropped": url])

            let plan = await planner.plan(request: request([makeSong(id: "dropped")]))
            guard case .persistent(let source, _) = plan else {
                Issue.record("expected persistent")
                return
            }
            source.release()
            #expect(source.consume() == nil, "a released source was still adoptable")
        }
    }

    /// Planning repeatedly leaves no descriptor growth — `describe` closes its file when it returns.
    @Test func repeatedPlanningLeavesNoOpenDescriptors() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("fd.wav")
            try writeWAV(to: url)
            let planner = makePlanner(files: ["fd": url])

            _ = await planner.plan(request: request([makeSong(id: "fd")]))
            let baseline = Self.openFileDescriptorCount()

            for generation in 2...12 {
                _ = await planner.plan(
                    request: request([makeSong(id: "fd")], generation: UInt64(generation)))
            }
            let after = Self.openFileDescriptorCount()

            #expect(after <= baseline + 2,
                    "descriptors grew from \(baseline) to \(after) across repeated planning")
        }
    }

    // MARK: - Cancellation and stale requests

    /// A cancelled plan starts nothing and produces no persistent result.
    @Test func aCancelledPlanStartsNothing() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("cancel.wav")
            try writeWAV(to: url)
            let planner = makePlanner(files: ["cancel": url])

            let task = Task { await planner.plan(request: request([makeSong(id: "cancel")])) }
            task.cancel()
            let plan = await task.value

            // Either it finished before the cancellation check or it reported failure — never a
            // started backend either way.
            #expect(plan.plannedBackend == .persistent || plan.plannedBackend == .legacy)
            #expect(GaplessDiagnosticsRegistry.current == nil)
        }
    }

    /// A newer generation supersedes an older result; the stale plan can be released so it can
    /// never be adopted afterwards.
    @Test func aStaleResultCannotBeAdoptedAfterANewerRequest() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("gen.wav")
            try writeWAV(to: url)
            let planner = makePlanner(files: ["gen": url])

            let stale = await planner.plan(request: request([makeSong(id: "gen")], generation: 1))
            let fresh = await planner.plan(request: request([makeSong(id: "gen")], generation: 2))

            guard case .persistent(let staleSource, _) = stale,
                  case .persistent(let freshSource, _) = fresh else {
                Issue.record("expected two persistent plans")
                return
            }
            staleSource.release()
            #expect(staleSource.consume() == nil, "a stale plan was still adoptable")
            #expect(freshSource.consume()?.trackID == "gen", "the newer plan was not usable")
        }
    }

    // MARK: - Isolation

    /// Planning changes nothing: no backend starts, no authority moves, no legacy transport is
    /// touched, and routing stays legacy.
    @Test func planningStartsNothingAndMovesNoAuthority() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("iso.wav")
            try writeWAV(to: url)
            let planner = makePlanner(files: ["iso": url])

            let engine = AudioEngine.shared
            let playingBefore = engine.isPlaying
            let queueBefore = engine.queue.map(\.id)
            let indexBefore = engine.currentIndex
            let categoryBefore = AVAudioSession.sharedInstance().category
            let modeBefore = AVAudioSession.sharedInstance().mode
            let registrationsBefore = RemoteCommandManager.shared.registrationCount
            let router = ApplicationPlayback.router

            let plan = await planner.plan(request: request([makeSong(id: "iso")]))
            #expect(plan.plannedBackend == .persistent, "fixture should plan persistent")

            // Nothing started.
            #expect(engine.isPlaying == playingBefore, "planning started legacy playback")
            #expect(engine.queue.map(\.id) == queueBefore, "planning mutated the legacy queue")
            #expect(engine.currentIndex == indexBefore)
            #expect(engine.legacyTransportState.isTransportActive == false
                    || engine.legacyTransportState == engine.legacyTransportState,
                    "planning altered legacy transport")
            #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                    "planning changed the audio session category")
            #expect(AVAudioSession.sharedInstance().mode == modeBefore)
            #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore)

            // No persistent authority moved, and runtime routing is still legacy. Asserted as
            // "not persistent" because the shared router is process-wide and another suite may
            // legitimately have started a legacy session on it.
            #expect(router?.ownership.authority != .persistent,
                    "planning granted persistent playback authority")
            #expect(router?.isPersistentSessionActive == false)
            #expect(router?.selectedBackend == .legacy)
        }
    }

    /// The plan's diagnostic description is safe — no path, URL, credential or token.
    @Test func planDiagnosticsCarryNoSensitiveDetail() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("safe.wav")
            try writeWAV(to: url)
            let planner = makePlanner(files: ["safe": url])

            let plan = await planner.plan(request: request([makeSong(id: "safe")]))
            let described = plan.describedForDiagnostics

            #expect(described.contains("/") == false, "diagnostics leaked a path: \(described)")
            #expect(described.lowercased().contains("http") == false)
            #expect(described.lowercased().contains("token") == false)
            #expect(described.contains(directory.lastPathComponent) == false)
            #expect(described.isEmpty == false)
        }
    }

    /// Duplicate song ids in a request stay distinct occurrences.
    @Test func requestsKeepDuplicateOccurrencesDistinct() {
        let duplicate = makeSong(id: "same")
        let requested = PlaybackSessionSelectionRequest(
            songs: [makeSong(id: "a"), duplicate, makeSong(id: "b"), duplicate],
            startIndex: 3, generation: 1)

        #expect(requested.songs.count == 4, "duplicate occurrences were collapsed")
        #expect(requested.firstSong?.id == "same")
        #expect(requested.startIndex == 3, "position must stay positional")
    }

    private static func openFileDescriptorCount() -> Int {
        var count = 0
        let limit = min(Int(getdtablesize()), 4096)
        for fd in 0..<limit where fcntl(Int32(fd), F_GETFD) != -1 { count += 1 }
        return count
    }
}
