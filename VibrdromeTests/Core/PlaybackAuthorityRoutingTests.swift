import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Lane 3D-B1: the router starts sessions through the planner and executor, then sends transport to
/// whichever backend holds authority.
///
/// **The property under test is a count, not a destination.** One application operation must produce
/// exactly one operation on the backend that owns the session and *zero* on the other one. A command
/// that reaches both is not a cosmetic bug: the inactive engine would advance its own queue, so the
/// two would disagree about what is playing and the next boundary would be attributed to the wrong
/// track.
///
/// **Every test builds its own router.** `ApplicationPlayback.shared` is process-wide and the
/// serialized gate may enter with `AudioEngine.shared` left playing by another suite, so nothing
/// here reads or mutates the shared composition point, and each test cleans up both backends.
@Suite(.serialized)
@MainActor
struct PlaybackAuthorityRoutingTests {

    private static let sampleRate = GaplessBufferFixtures.sampleRate
    private static let trackFrames = 44_100

    // MARK: - Fixtures

    private func makeSong(id: String) -> Song {
        Song(id: id, parent: nil, title: "Track \(id)",
             album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
             track: nil, year: nil, genre: nil, coverArt: nil,
             size: nil, contentType: nil, suffix: nil,
             duration: 1, bitRate: nil, path: nil,
             discNumber: nil, created: nil, starred: nil, userRating: nil,
             bpm: nil, replayGain: nil, musicBrainzId: nil)
    }

    private func makeStation() -> InternetRadioStation {
        InternetRadioStation(id: "r1", name: "Probe FM",
                             streamUrl: "https://example.invalid/stream",
                             homePageUrl: nil, coverArt: nil)
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("route-\(UInt64.random(in: 0..<UInt64.max))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func makeFiles(_ ids: [String], in directory: URL) throws -> [String: URL] {
        var files: [String: URL] = [:]
        for (index, id) in ids.enumerated() {
            let url = directory.appendingPathComponent("\(id).wav")
            try GaplessBufferFixtures.writeStereoWav(
                url: url, frequency: 440 + Double(index) * 110,
                frames: Self.trackFrames, sampleRate: Self.sampleRate)
            files[id] = url
        }
        return files
    }

    /// A router whose legacy backend is a recorder and whose persistent side is a recorder.
    ///
    /// Neither opens a real player: this suite is about *where a command lands*, and starting real
    /// server playback would both prove nothing extra and leave transport running for the next
    /// suite. Tests that are about planning use `makePlanningRouter` and real media instead.
    private func makeRoutingRouter()
        -> (ApplicationPlaybackRouter, PlaybackSpy, PersistentTransportSpy) {
        let legacy = PlaybackSpy()
        let transport = PersistentTransportSpy()
        let router = ApplicationPlaybackRouter(legacy: legacy,
                                               persistentBuilder: RefusingAssemblyBuilder())
        router.persistentPortOverrideForTesting = PersistentPortDouble(transport: transport)
        return (router, legacy, transport)
    }

    /// Drive a router into a settled persistent session without any real media, by handing it a
    /// finalized persistent plan.
    private func startPersistentSession(
        _ router: ApplicationPlaybackRouter, songs: [Song], track: GaplessPreparedTrack
    ) async {
        router.planOverrideForTesting = { _ in
            .persistent(preparedSource: PreparedPersistentSource(track: track,
                                                                 deliveredContainer: "wav"),
                        decision: PlaybackBackendDecision(backend: .persistent,
                                                          playableByPersistentEngine: true,
                                                          gaplessCapable: true,
                                                          reason: .supportedLocalSource))
        }
        PersistentRoutingSetting.setEnabled(true)
        router.play(song: songs[0], from: songs, at: 0)
        await router.awaitPendingSelectionForTesting()
    }

    /// A prepared track over a real file, so a plan carries a real source rather than a fabricated
    /// one even when the test is about routing.
    private func makeTrack(id: String, in directory: URL) throws -> GaplessPreparedTrack {
        let url = directory.appendingPathComponent("\(id).wav")
        try GaplessBufferFixtures.writeStereoWav(
            url: url, frequency: 440, frames: Self.trackFrames, sampleRate: Self.sampleRate)
        return try GaplessTrackPreparer.describe(trackID: id, fileURL: url,
                                                 renderSampleRate: Self.sampleRate)
    }

    /// Restore the DEBUG flag whatever the test did with it.
    private func withRoutingFlag(_ enabled: Bool, _ body: () async throws -> Void) async rethrows {
        let before = PersistentRoutingSetting.isEnabled
        defer { PersistentRoutingSetting.setEnabled(before) }
        PersistentRoutingSetting.setEnabled(enabled)
        try await body()
    }

    // MARK: - Flag Off and Release

    /// Off is today's behaviour exactly: no planning, no persistent construction, one legacy start.
    @Test func flagOffStartsLegacyWithoutPlanning() async {
        await withRoutingFlag(false) {
            let (router, legacy, persistent) = makeRoutingRouter()
            let constructedBefore = PersistentPlaybackAssembly.constructionCount
            let song = makeSong(id: "a")

            router.play(song: song, from: [song], at: 0)
            await router.awaitPendingSelectionForTesting()

            #expect(legacy.playCalls.count == 1,
                    "legacy was started \(legacy.playCalls.count) times")
            #expect(legacy.playCalls.first?.songId == "a")
            #expect(persistent.calls.isEmpty, "flag Off reached persistent: \(persistent.calls)")
            #expect(PersistentPlaybackAssembly.constructionCount == constructedBefore,
                    "flag Off constructed a persistent assembly")
            #expect(router.ownership.authority == PlaybackAuthority.none,
                    "flag Off moved playback authority")
            #expect(router.selectedBackend == .legacy)
        }
    }

    /// The beta preference is one key, identical in every build configuration — no `#if DEBUG`
    /// fork — which is what makes the Release opt-in reachable. Its key is the fresh
    /// `gaplessEngineBeta`, deliberately NOT the old debug key, so a prior debug opt-in cannot leak
    /// into Release.
    @Test func gaplessBetaPreferenceIsOneReleaseVisibleKey() {
        #expect(PersistentRoutingSetting.defaultsKey == "gaplessEngineBeta")
        #expect(PersistentRoutingSetting.defaultsKey == UserDefaultsKeys.gaplessEngineBeta)
        #expect(PersistentRoutingSetting.defaultsKey != "debugUsePersistentPlaybackEngine",
                "the old DEBUG key must not govern the Release beta")
        // A router that has planned nothing owns nothing, whatever the preference says.
        let (router, _, _) = makeRoutingRouter()
        #expect(router.selectedBackend == .legacy)
        #expect(router.ownership.authority == PlaybackAuthority.none)
    }

    /// A router that has never been asked to play starts nothing — the cold-launch property.
    @Test func coldLaunchStartsNothing() {
        let (router, legacy, persistent) = makeRoutingRouter()

        #expect(router.pendingPlanningGeneration == 0)
        #expect(router.lastCompletedPlanningGeneration == 0)
        #expect(router.sessionSelectionState == .idle)
        #expect(router.ownership.authority == PlaybackAuthority.none)
        #expect(legacy.playCalls.isEmpty)
        #expect(persistent.calls.isEmpty)
        #expect(router.persistentPreparationState == .notConstructed)
    }

    // MARK: - Planning results

    /// A real eligible source plans persistent and is executed once, on the real stack.
    @Test func anEligibleSourceIsPlannedAndExecutedOnce() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["p0"], in: directory)
                let legacy = PlaybackSpy()
                let router = ApplicationPlaybackRouter(
                    legacy: legacy,
                    persistentBuilder: LocalFileAssemblyBuilder(files: files, directory: directory))
                defer { scheduleTeardown(router) }
                let song = makeSong(id: "p0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()

                #expect(router.ownership.authority == .persistent,
                        "an eligible source settled as \(router.sessionSelectionState.describedForDiagnostics)")
                #expect(router.selectedBackend == .persistent)
                #expect(legacy.playCalls.isEmpty, "legacy was started for a persistent session")
                #expect(router.lastCompletedPlanningGeneration == 1)
                #expect(router.isReplacingSession == false, "the replacement never completed")
                // Real audio played on a real assembly: release it to completion before the next
                // serialized test, rather than leaving the scheduled defer racing it.
                await teardown(router)
            }
        }
    }

    /// The Release-equivalent pair for `anEligibleSourceIsPlannedAndExecutedOnce`: the *same* real
    /// eligible source, but with beta opt-in OFF, must stay Legacy and construct no persistent
    /// stack. Together these two prove the opt-in gate opens and closes the Release path through
    /// the real `PersistentRoutingSetting` preference — not an injected test closure. There is no
    /// `#if DEBUG` fork in that preference, so this is exactly the Release behavior.
    @Test func anEligibleSourceWithBetaOffStaysLegacyAndConstructsNothing() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(false) {
                let files = try makeFiles(["p0"], in: directory)
                let legacy = PlaybackSpy()
                let router = ApplicationPlaybackRouter(
                    legacy: legacy,
                    persistentBuilder: LocalFileAssemblyBuilder(files: files, directory: directory))
                defer { scheduleTeardown(router) }
                let song = makeSong(id: "p0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()

                #expect(router.selectedBackend == .legacy,
                        "beta OFF must keep an eligible source on Legacy")
                #expect(router.ownership.authority != .persistent)
                #expect(legacy.playCalls.count == 1, "Legacy did not start the source")
                #expect(router.persistentAssembly == nil,
                        "beta OFF constructed the persistent stack for an eligible source")
                #expect(router.persistentPreparationState == .notConstructed,
                        "beta OFF left the audio domain non-lazy")
                #expect(GaplessDiagnosticsRegistry.current == nil)
            }
        }
    }

    /// A source the policy refuses plans legacy, and starts legacy exactly once.
    @Test func aRefusedSourcePlansLegacyAndStartsLegacyOnce() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                // Six channels: refused on the confirmed channel count, after real inspection.
                let url = directory.appendingPathComponent("surround.wav")
                try GaplessBufferFixtures.writeWav(
                    url: url, frequency: 440, frames: Self.trackFrames,
                    sampleRate: Self.sampleRate, channelCount: 6)
                let legacy = PlaybackSpy()
                let router = ApplicationPlaybackRouter(
                    legacy: legacy,
                    persistentBuilder: LocalFileAssemblyBuilder(files: ["s0": url],
                                                                directory: directory))
                defer { scheduleTeardown(router) }
                let song = makeSong(id: "s0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()

                #expect(router.ownership.authority == .legacy)
                #expect(router.selectedBackend == .legacy)
                #expect(legacy.playCalls.count == 1,
                        "legacy was started \(legacy.playCalls.count) times")
                // A real assembly inspected real media here; release it to completion.
                await teardown(router)
            }
        }
    }

    /// A `.failed` plan is legacy-owned: refusing to start would leave a Play press doing nothing.
    @Test func aFailedPlanStartsLegacyOnce() async {
        await withRoutingFlag(true) {
            let (router, legacy, persistent) = makeRoutingRouter()
            defer { scheduleTeardown(router) }
            router.planOverrideForTesting = { _ in .failed(reason: .sourcePreparationFailed) }
            let song = makeSong(id: "a")

            router.play(song: song, from: [song], at: 0)
            await router.awaitPendingSelectionForTesting()

            #expect(legacy.playCalls.count == 1)
            #expect(persistent.calls.contains("start") == false)
            #expect(router.ownership.authority == .legacy)
        }
    }

    /// A mid-track start goes to legacy without planning: persistent has no resume path, and legacy
    /// cannot be started-then-seeked because its item swap is deferred.
    @Test func aMidTrackStartRoutesToLegacyWithoutPlanning() async {
        await withRoutingFlag(true) {
            let (router, legacy, persistent) = makeRoutingRouter()
            defer { scheduleTeardown(router) }
            var planned = false
            router.planOverrideForTesting = { _ in
                planned = true
                return .legacy(reason: .supportedLocalSource)
            }
            let song = makeSong(id: "a")

            router.beginSession(songs: [song], startIndex: 0, startOffsetSeconds: 42)
            await router.awaitPendingSelectionForTesting()

            #expect(planned == false, "a mid-track start invoked the planner")
            #expect(legacy.playCalls.count == 1)
            #expect(persistent.calls.isEmpty)
        }
    }

    // MARK: - Generations

    /// A stale planner result starts nothing and releases its prepared source.
    @Test func aStaleGenerationStartsNothing() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, legacy, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                let track = try makeTrack(id: "a", in: directory)
                let source = PreparedPersistentSource(track: track, deliveredContainer: "wav")
                // The plan resolves only after a newer request has already superseded it.
                router.planOverrideForTesting = { _ in
                    router.beginSession(songs: [self.makeSong(id: "b")], startIndex: 0)
                    return .persistent(
                        preparedSource: source,
                        decision: PlaybackBackendDecision(backend: .persistent,
                                                          playableByPersistentEngine: true,
                                                          gaplessCapable: true,
                                                          reason: .supportedLocalSource))
                }
                let song = makeSong(id: "a")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()

                #expect(source.consume() == nil, "a superseded plan stayed adoptable")
                #expect(persistent.calls.contains("start") == false,
                        "a superseded plan started persistent: \(persistent.calls)")
                #expect(legacy.playCalls.count <= 1,
                        "a superseded plan produced \(legacy.playCalls.count) legacy starts")
            }
        }
    }

    /// Rapid consecutive Play requests: only the newest may execute, and there is never more than
    /// one authority or one audible start.
    @Test func rapidPlayRequestsExecuteOnlyTheNewest() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, _, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                let track = try makeTrack(id: "x", in: directory)
                var sources: [PreparedPersistentSource] = []
                router.planOverrideForTesting = { request in
                    let source = PreparedPersistentSource(track: track, deliveredContainer: "wav")
                    sources.append(source)
                    // Yield so an older plan can still be in flight when a newer request arrives.
                    await Task.yield()
                    _ = request
                    return .persistent(
                        preparedSource: source,
                        decision: PlaybackBackendDecision(backend: .persistent,
                                                          playableByPersistentEngine: true,
                                                          gaplessCapable: true,
                                                          reason: .supportedLocalSource))
                }

                for index in 0..<5 {
                    let song = makeSong(id: "r\(index)")
                    router.play(song: song, from: [song], at: 0)
                }
                await router.awaitPendingSelectionForTesting()

                #expect(router.pendingPlanningGeneration == 5,
                        "generations were \(router.pendingPlanningGeneration), expected 5")
                #expect(router.lastCompletedPlanningGeneration == 5,
                        "an older generation was the one that executed")
                let starts = persistent.calls.filter { $0 == "start" }.count
                #expect(starts <= 1, "rapid requests produced \(starts) persistent starts")
                #expect(router.ownership.ownerCount <= 1)
                // Every superseded source was released rather than left adoptable.
                let adoptable = sources.filter { !$0.isConsumed }.count
                #expect(adoptable == 0, "\(adoptable) superseded sources stayed adoptable")
            }
        }
    }

    // MARK: - Transport routing

    /// Every transport operation reaches persistent exactly once, and legacy not at all.
    @Test func transportRoutesToPersistentAndNeverToLegacy() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, legacy, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                let songs = [makeSong(id: "t0"), makeSong(id: "t1")]
                let track = try makeTrack(id: "t0", in: directory)
                await startPersistentSession(router, songs: songs, track: track)
                #expect(router.ownership.authority == .persistent, "the fixture never took authority")

                legacy.resetForTesting()
                persistent.reset()

                router.pause()
                router.resume()
                router.togglePlayPause()
                router.next()
                router.previous()
                router.seek(to: 12)
                router.skipToIndex(1)
                router.stop()
                router.addToQueue(makeSong(id: "n0"))
                router.addToQueueNext(makeSong(id: "n1"))
                router.removeFromQueue(atAbsolute: 0)
                router.moveInUpNext(from: IndexSet(integer: 0), to: 1)
                router.clearQueue()
                router.cycleRepeatMode()
                router.toggleShuffle()
                router.applyEQToggle(enabled: true)
                router.applyEffectiveVolume()
                router.userVolume = 0.4

                for operation in ["pause", "resume", "togglePlayPause", "next", "previous", "seek",
                                  "skipToIndex", "stop", "addToQueue", "addToQueueNext",
                                  "removeFromQueue", "moveInUpNext", "clearQueue", "setRepeatMode",
                                  "setShuffleEnabled", "applyEQToggle", "applyEffectiveVolume",
                                  "userVolume"] {
                    let count = persistent.calls.filter { $0 == operation }.count
                    #expect(count == 1,
                            "\(operation) produced \(count) persistent operations, expected 1")
                }
                #expect(legacy.calls.isEmpty,
                        "the inactive legacy backend received \(legacy.calls)")
                #expect(legacy.playCalls.isEmpty)
            }
        }
    }

    /// Durations and buffering follow authority: during a persistent session they come from the
    /// persistent side, never from the quiesced legacy engine — whose stale duration is how the
    /// full player showed 0:00 remaining early while audio continued (device capture, 2026-08-29).
    @Test func durationsRouteToPersistentWhileItOwnsTheSession() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, _, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                let track = try makeTrack(id: "d0", in: directory)
                await startPersistentSession(router, songs: [makeSong(id: "d0")], track: track)
                #expect(router.ownership.authority == .persistent, "the fixture never took authority")

                persistent.duration = 123
                persistent.effectiveDuration = 456

                #expect(router.duration == 123, "duration was not answered by the session owner")
                #expect(router.effectiveDuration == 456)
                #expect(router.isBuffering == false,
                        "a persistent session reported the legacy engine's buffering state")
            }
        }
    }

    /// The visualizer ownership gate follows authority, and the two publishers are mutually
    /// exclusive in every state — including `.none`, where legacy keeps its historical right to
    /// publish (the flag-off production path plays with no explicit grant).
    @Test func visualizerPublicationFollowsAuthority() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, _, _) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                let gate = VisualizerOwnershipGate.shared

                // Cold state: no authority — legacy publishes, persistent must not.
                router.ownership.release()
                #expect(gate.legacyMayPublish)
                #expect(gate.persistentMayPublish == false)

                let track = try makeTrack(id: "v0", in: directory)
                await startPersistentSession(router, songs: [makeSong(id: "v0")], track: track)
                #expect(router.ownership.authority == .persistent)
                #expect(gate.persistentMayPublish, "persistent authority did not open its gate")
                #expect(gate.legacyMayPublish == false,
                        "legacy could still publish under persistent authority")

                // Radio replaces the session: teardown is awaited, then legacy owns — and the gate
                // must flip with the authority, never leaving both open.
                router.startRadio(artistName: "Probe")
                await router.awaitPendingSelectionForTesting()
                #expect(router.ownership.authority == .legacy)
                #expect(gate.legacyMayPublish)
                #expect(gate.persistentMayPublish == false,
                        "persistent could still publish after losing the session")
                #expect(!(gate.legacyMayPublish && gate.persistentMayPublish),
                        "both publishers were open at once")
            }
        }
    }

    /// With no persistent session, the same operations reach legacy exactly once and persistent not
    /// at all.
    @Test func transportRoutesToLegacyWhenPersistentDoesNotOwnTheSession() {
        let (router, legacy, persistent) = makeRoutingRouter()
        defer { scheduleTeardown(router) }

        router.pause()
        router.resume()
        router.next()
        router.previous()
        router.seek(to: 3)
        router.togglePlayPause()

        for operation in ["pause", "resume", "next", "previous", "seek", "togglePlayPause"] {
            let count = legacy.calls.filter { $0 == operation }.count
            #expect(count == 1, "\(operation) produced \(count) legacy operations, expected 1")
        }
        #expect(persistent.calls.isEmpty,
                "the inactive persistent backend received \(persistent.calls)")
    }

    /// Every queue projection resolves against the **same** backend as the queue itself.
    ///
    /// Regression: `nextSongIndex()` stayed on legacy while `queue` routed to persistent, so the
    /// mini player subscripted one backend's array with the other's index and trapped in
    /// `Array._checkSubscript`. Legacy is deliberately left holding a longer, different queue here —
    /// which is exactly what a legacy session played before a persistent one leaves behind.
    @Test func queueProjectionsResolveAgainstTheActiveBackendsQueue() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, legacy, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                legacy.queue = (0..<40).map { makeSong(id: "stale\($0)") }
                legacy.currentIndex = 30

                let songs = ["q0", "q1", "q2"].map { makeSong(id: $0) }
                let track = try makeTrack(id: "q0", in: directory)
                await startPersistentSession(router, songs: songs, track: track)
                persistent.queue = songs
                persistent.currentIndex = 0

                #expect(router.queue.count == 3,
                        "the router read the stale legacy queue during a persistent session")
                if let next = router.nextSongIndex() {
                    #expect(router.queue.indices.contains(next),
                            "nextSongIndex() returned \(next), out of range for a \(router.queue.count)-item queue")
                }
                for entry in router.upNextEntries {
                    #expect(router.queue.indices.contains(entry.index),
                            "upNextEntries carried index \(entry.index), out of range")
                }
                #expect(router.upNext.count <= router.queue.count)
            }
        }
    }

    /// State the active backend can answer is read from it, not from the quiesced legacy engine.
    @Test func observableStateFollowsTheActiveBackend() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, legacy, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                let songs = [makeSong(id: "s0"), makeSong(id: "s1")]
                let track = try makeTrack(id: "s0", in: directory)
                await startPersistentSession(router, songs: songs, track: track)

                persistent.isPlaying = true
                persistent.currentSong = songs[1]
                persistent.currentIndex = 1
                legacy.isPlaying = false
                legacy.currentSong = makeSong(id: "stale")

                #expect(router.isPlaying, "the router reported the quiesced legacy engine's state")
                #expect(router.currentSong?.id == "s1")
                #expect(router.currentIndex == 1)
            }
        }
    }

    // MARK: - Session replacement

    /// Persistent → Legacy: persistent is torn down, its callback cleared, authority revoked, and a
    /// **new** legacy session started rather than a stale one resumed.
    @Test func persistentIsReplacedByANewLegacySession() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, legacy, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                let track = try makeTrack(id: "p0", in: directory)
                await startPersistentSession(router, songs: [makeSong(id: "p0")], track: track)
                #expect(router.ownership.authority == .persistent)

                legacy.resetForTesting()
                persistent.reset()
                router.planOverrideForTesting = { _ in .legacy(reason: .decoderUnavailable) }
                let song = makeSong(id: "legacy-only")
                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()

                #expect(router.ownership.authority == .legacy)
                #expect(persistent.calls.contains("tearDown"),
                        "the persistent session was left running: \(persistent.calls)")
                #expect(persistent.calls.contains("clearObserver"),
                        "the old session's audible callback was left installed")
                // A fresh session, from the request — never a resumed stale item.
                #expect(legacy.playCalls.count == 1,
                        "legacy was started \(legacy.playCalls.count) times")
                #expect(legacy.playCalls.first?.songId == "legacy-only")
                #expect(legacy.calls.contains("resume") == false,
                        "the replacement resumed a stale legacy session")
            }
        }
    }

    /// Legacy → Persistent: the executor's handoff, reached through the router.
    @Test func legacyIsReplacedByAPersistentSession() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, legacy, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                router.planOverrideForTesting = { _ in .legacy(reason: .supportedLocalSource) }
                let first = makeSong(id: "l0")
                router.play(song: first, from: [first], at: 0)
                await router.awaitPendingSelectionForTesting()
                #expect(router.ownership.authority == .legacy)

                let track = try makeTrack(id: "p0", in: directory)
                persistent.reset()
                await startPersistentSession(router, songs: [makeSong(id: "p0")], track: track)

                #expect(router.ownership.authority == .persistent)
                #expect(persistent.calls.filter { $0 == "start" }.count == 1)
                #expect(legacy.playCalls.count == 1,
                        "the handoff started legacy again (\(legacy.playCalls.count) starts)")
            }
        }
    }

    /// Persistent → Persistent: the old session is released before the new one is executed, and the
    /// old prepared source is never reused.
    @Test func persistentIsReplacedByANewPersistentSession() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, _, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                let first = try makeTrack(id: "p0", in: directory)
                await startPersistentSession(router, songs: [makeSong(id: "p0")], track: first)
                persistent.reset()

                let second = try makeTrack(id: "p1", in: directory)
                await startPersistentSession(router, songs: [makeSong(id: "p1")], track: second)

                #expect(router.ownership.authority == .persistent)
                #expect(persistent.calls.filter { $0 == "tearDown" }.count == 1,
                        "the old persistent session was not released: \(persistent.calls)")
                #expect(persistent.calls.filter { $0 == "start" }.count == 1,
                        "the replacement produced more than one start")
                // The tear-down happened before the new adoption.
                let teardownIndex = persistent.calls.firstIndex(of: "tearDown") ?? Int.max
                let adoptIndex = persistent.calls.firstIndex(of: "adopt") ?? -1
                #expect(teardownIndex < adoptIndex,
                        "the new session was adopted before the old one let go: \(persistent.calls)")
                #expect(persistent.adoptedTracks.last?.trackID == "p1",
                        "the replacement reused the old prepared source")
            }
        }
    }

    // MARK: - Radio

    /// Radio is always a new legacy session, and releases persistent first.
    @Test func radioAlwaysBecomesANewLegacySession() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, legacy, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                let track = try makeTrack(id: "p0", in: directory)
                await startPersistentSession(router, songs: [makeSong(id: "p0")], track: track)
                legacy.resetForTesting()
                persistent.reset()

                router.startRadio(artistName: "Probe")
                // Replacing a live persistent session is this request's ordered transition: the
                // persistent teardown is awaited to completion before legacy is granted and
                // started, and this is the seam that awaits it.
                await router.awaitPendingSelectionForTesting()

                #expect(router.ownership.authority == .legacy)
                #expect(persistent.calls.contains("tearDown"))
                #expect(persistent.calls.contains("clearObserver"))
                #expect(persistent.calls.contains("start") == false,
                        "radio reached the persistent engine")
                #expect(legacy.calls.filter { $0 == "startRadio" }.count == 1,
                        "radio started \(legacy.calls.filter { $0 == "startRadio" }.count) times")
            }
        }
    }

    /// Every radio entry point behaves the same way, and none of them plans.
    @Test func everyRadioEntryPointStartsExactlyOneLegacySession() async {
        await withRoutingFlag(true) {
            let (router, legacy, persistent) = makeRoutingRouter()
            defer { scheduleTeardown(router) }
            var planned = false
            router.planOverrideForTesting = { _ in
                planned = true
                return .legacy(reason: .supportedLocalSource)
            }

            router.startRadio(artistName: "A")
            router.startRadioFromSong(makeSong(id: "s"))
            router.startSongSimilarityMix(makeSong(id: "s"))
            router.playRadio(station: makeStation())

            #expect(planned == false, "a radio request went through the persistent planner")
            for operation in ["startRadio", "startRadioFromSong", "startSongSimilarityMix",
                              "playRadio"] {
                let count = legacy.calls.filter { $0 == operation }.count
                #expect(count == 1, "\(operation) produced \(count) legacy operations")
            }
            #expect(persistent.calls.contains("start") == false)
        }
    }

    // MARK: - No mid-session switching

    /// Changing the flag does not move the session that is already playing.
    @Test func aFlagChangeAffectsOnlyTheNextNewSession() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, legacy, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                let track = try makeTrack(id: "p0", in: directory)
                await startPersistentSession(router, songs: [makeSong(id: "p0")], track: track)
                #expect(router.ownership.authority == .persistent)

                PersistentRoutingSetting.setEnabled(false)
                persistent.reset()
                legacy.resetForTesting()

                // The live session keeps its backend, and its transport keeps going there.
                router.pause()
                router.next()

                #expect(router.ownership.authority == .persistent,
                        "turning the flag off moved a live session")
                #expect(persistent.calls.filter { $0 == "pause" }.count == 1)
                #expect(legacy.calls.isEmpty, "a live session's transport went to legacy")
            }
        }
    }

    /// Resume, Toggle, Next and Previous never plan — they continue the existing session.
    @Test func continuingOperationsNeverPlan() async {
        await withRoutingFlag(true) {
            let (router, _, _) = makeRoutingRouter()
            defer { scheduleTeardown(router) }
            var planCount = 0
            router.planOverrideForTesting = { _ in
                planCount += 1
                return .legacy(reason: .supportedLocalSource)
            }
            let song = makeSong(id: "a")
            router.play(song: song, from: [song], at: 0)
            await router.awaitPendingSelectionForTesting()
            #expect(planCount == 1)

            router.resume()
            router.togglePlayPause()
            router.next()
            router.previous()
            router.seek(to: 5)
            await router.awaitPendingSelectionForTesting()

            #expect(planCount == 1,
                    "a continuing operation re-planned the session (\(planCount) plans)")
            #expect(router.pendingPlanningGeneration == 1,
                    "a continuing operation took a planning generation")
        }
    }

    /// A post-audible persistent failure cannot fall back: a cutover mid-track is worse than an
    /// error, so persistent keeps the session.
    @Test func aPostAudibleFailureCannotFallBack() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, legacy, persistent) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                persistent.becomesAudibleBeforeFailing = true
                persistent.startFailure = GaplessEngineFailure.engineStartFailed("after audio")
                let track = try makeTrack(id: "p0", in: directory)

                await startPersistentSession(router, songs: [makeSong(id: "p0")], track: track)

                #expect(router.ownership.authority == .persistent,
                        "the session was cut over after the listener had heard persistent")
                #expect(router.ownership.audibleBoundaryReached)
                #expect(router.ownership.isFallbackPermitted == false)
                #expect(legacy.playCalls.isEmpty,
                        "legacy was started under audible persistent audio")
            }
        }
    }

    // MARK: - Diagnostics

    /// The diagnostics report the routing state, and keep saying the signal integrations are not
    /// done.
    @Test func diagnosticsReportRoutingStateAndPendingSignals() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let (router, _, _) = makeRoutingRouter()
                defer { scheduleTeardown(router) }
                let track = try makeTrack(id: "p0", in: directory)
                await startPersistentSession(router, songs: [makeSong(id: "p0")], track: track)

                let diagnostics = router.diagnostics
                #expect(diagnostics.authority == .persistent)
                #expect(diagnostics.selectedBackend == .persistent)
                #expect(diagnostics.pendingPlanningGeneration == 1)
                #expect(diagnostics.lastCompletedPlanningGeneration == 1)
                #expect(diagnostics.isReplacingSession == false)
                #expect(diagnostics.isFallbackPermitted)
                #expect(diagnostics.audibleBoundaryReached == false)

                let summary = diagnostics.summary
                #expect(summary.contains("Playback authority: persistent"))
                #expect(summary.contains("Active transport backend: Persistent"))
                #expect(summary.lowercased().contains("single owner"),
                        "the summary stopped stating the single-owner signal contract")
                #expect(summary.contains("/") == false || summary.lowercased().contains("scrobble"),
                        "diagnostics leaked something path-like: \(summary)")
            }
        }
    }

    // MARK: - Isolation

    /// This suite leaves no transport running on either backend.
    ///
    /// Asserted against the real shared engine and a real assembly, because that is what the next
    /// suite in the gate inherits — a routing test that left an engine playing would show up as an
    /// unrelated failure somewhere else.
    @Test func thisSuiteLeavesNoActiveTransportBehind() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["p0"], in: directory)
                let legacy = PlaybackSpy()
                let builder = LocalFileAssemblyBuilder(files: files, directory: directory)
                let router = ApplicationPlaybackRouter(legacy: legacy, persistentBuilder: builder)
                let song = makeSong(id: "p0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()
                #expect(router.ownership.authority == .persistent, "the fixture never started")

                await teardown(router)

                #expect(router.ownership.authority == PlaybackAuthority.none,
                        "teardown left authority granted")
                if let assembly = router.persistentAssembly {
                    #expect(assembly.backend.state == .idle,
                            "teardown left the persistent backend \(assembly.backend.state)")
                    #expect(assembly.backend.engine.engine.isRunning == false)
                    #expect(assembly.controller.onFirstAudibleSample == nil,
                            "teardown left an audible callback installed")
                    let snap = await assembly.backend.domainSnapshotForTesting
                    #expect(snap.poolInFlight == 0,
                            "teardown left pool buffers out")
                }
                #expect(PersistentRoutingSetting.isEnabled,
                        "the flag helper stopped restoring the DEBUG override")
            }
        }
        // And the shared legacy engine is not left holding transport by this suite.
        AudioEngine.shared.quiesceForPersistentSession()
        #expect(AudioEngine.shared.legacyTransportState.isTransportActive == false)
    }

    /// Release every resource a routing test may have taken: authority, persistent transport,
    /// the audible callback and any selection still in flight. Awaited, so on return the
    /// persistent side is genuinely clean.
    private func teardown(_ router: ApplicationPlaybackRouter) async {
        await router.releaseSessionForTesting()
    }

    /// Cleanup for `defer`, which cannot await: schedules the same release on the main actor.
    /// Spy-backed fixtures release in one hop, so this drains before the next serialized test does
    /// real work; tests that play real audio or assert post-release state await `teardown(_:)`
    /// explicitly instead (the scheduled release is idempotent behind it).
    private func scheduleTeardown(_ router: ApplicationPlaybackRouter) {
        Task { @MainActor in await router.releaseSessionForTesting() }
    }
}

// MARK: - Doubles

/// Records where persistent transport commands land, without an audio graph.
@MainActor
final class PersistentTransportSpy: PersistentTransportRouting {
    private(set) var calls: [String] = []
    /// The handoff sequence lands here too, so one ordered record shows both the ownership move and
    /// the commands that followed it.
    func record(_ name: String) { calls.append(name) }
    func reset() {
        calls.removeAll()
        adoptedTracks.removeAll()
    }

    /// Sources the port adopted, newest last.
    var adoptedTracks: [GaplessPreparedTrack] = []
    /// When set, the port's `start()` throws it.
    var startFailure: Error?
    /// When true, the port's `start()` fires the audible observer before failing.
    var becomesAudibleBeforeFailing = false

    func play(song: Song, from newQueue: [Song]?, at index: Int) { record("play") }
    func pause() { record("pause") }
    func resume() { record("resume") }
    func stop() { record("stop") }
    func togglePlayPause() { record("togglePlayPause") }
    func next() { record("next") }
    func previous() { record("previous") }
    func seek(to time: TimeInterval) { record("seek") }
    func skipToIndex(_ index: Int) { record("skipToIndex") }
    func addToQueue(_ song: Song) { record("addToQueue") }
    func addToQueueNext(_ song: Song) { record("addToQueueNext") }
    func removeFromQueue(atAbsolute index: Int) { record("removeFromQueue") }
    func moveInUpNext(from source: IndexSet, to destination: Int) { record("moveInUpNext") }
    func clearQueue() { record("clearQueue") }
    func replaceQueue(_ songs: [Song], startIndex: Int) { record("replaceQueue") }
    func setRepeatMode(_ mode: RepeatMode) {
        record("setRepeatMode")
        repeatMode = mode
    }
    func setShuffleEnabled(_ enabled: Bool) {
        record("setShuffleEnabled")
        shuffleEnabled = enabled
    }
    func applyEQToggle(enabled: Bool) {
        record("applyEQToggle")
        eqEnabled = enabled
    }
    func applyEffectiveVolume() { record("applyEffectiveVolume") }

    private var storedVolume: Float = 1
    var volume: Float {
        get { storedVolume }
        set {
            record("volume")
            storedVolume = newValue
        }
    }
    var userVolume: Float {
        get { storedVolume }
        set {
            record("userVolume")
            storedVolume = newValue
        }
    }
    var eqEnabled = false
    var isPlaying = false
    var currentSong: Song?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var effectiveDuration: TimeInterval = 0
    var visualizerActive: Bool = false {
        didSet { record("visualizerActive") }
    }
    var queue: [Song] = []
    var currentIndex = 0
    var repeatMode: RepeatMode = .off
    var shuffleEnabled = false

    /// The queue projections travel with `queue` and `currentIndex`, so the double answers them
    /// from the same array rather than from a second one.
    func nextSongIndex() -> Int? {
        queue.indices.contains(currentIndex + 1) ? currentIndex + 1 : nil
    }
    var upNext: [Song] {
        queue.indices.contains(currentIndex + 1) ? Array(queue[(currentIndex + 1)...]) : []
    }
    var upNextEntries: [(index: Int, song: Song)] {
        upNext.enumerated().map { (index: currentIndex + 1 + $0.offset, song: $0.element) }
    }

    /// Reported rather than driven: this double has no controller to tick, so the port double below
    /// keeps the counters and the heartbeat itself is covered by `PersistentHeartbeatTests`.
    var heartbeatDiagnostics = PersistentHeartbeatDiagnostics()
}

/// A handoff port over the transport spy, so a router can reach a persistent session without an
/// assembly. Records the handoff sequence the same way the executor's own spy does.
@MainActor
final class PersistentPortDouble: PersistentPlaybackSessionPort {
    let spy: PersistentTransportSpy
    private var observer: (@MainActor () -> Void)?

    init(transport: PersistentTransportSpy) { spy = transport }

    var transport: any PersistentTransportRouting { spy }
    var isTransportActive: Bool { spy.isPlaying }

    func adopt(_ snapshot: PlaybackSessionSnapshot) {
        spy.record("adopt")
        spy.queue = snapshot.songs
        spy.currentIndex = snapshot.currentIndex
    }

    func adopt(preparedSource: GaplessPreparedTrack) async {
        spy.record("adoptPreparedSource")
        spy.adoptedTracks.append(preparedSource)
    }

    func installAudibleObserver(_ observer: @escaping @MainActor () -> Void) {
        spy.record("installObserver")
        self.observer = observer
    }

    func clearAudibleObserver() {
        spy.record("clearObserver")
        observer = nil
    }

    func start(sessionGeneration: UInt64) async throws {
        spy.record("start")
        if spy.becomesAudibleBeforeFailing { observer?() }
        if let failure = spy.startFailure { throw failure }
        spy.isPlaying = true
        // The double owns no controller, so it reports what a heartbeat would have done rather than
        // running one — enough for the router-level "started once, cancelled on replacement"
        // assertions, while the real loop is proven in `PersistentHeartbeatTests`.
        spy.heartbeatDiagnostics.isRunning = true
        spy.heartbeatDiagnostics.sessionGeneration = sessionGeneration
        spy.heartbeatDiagnostics.startCount += 1
    }

    func tearDown(preserveAudioSession: Bool) async {
        spy.record("tearDown")
        spy.isPlaying = false
        if spy.heartbeatDiagnostics.isRunning {
            spy.heartbeatDiagnostics.isRunning = false
            spy.heartbeatDiagnostics.cancellationCount += 1
        }
    }
}

/// A builder that refuses, for routers whose persistent side is overridden anyway.
@MainActor
struct RefusingAssemblyBuilder: PersistentPlaybackAssemblyBuilding {
    func build() throws -> PersistentPlaybackAssembly {
        throw PersistentPreparationFailure.builderRefused
    }
}

/// A real assembly over local files, for the tests that are about planning.
@MainActor
struct LocalFileAssemblyBuilder: PersistentPlaybackAssemblyBuilding {
    let files: [String: URL]
    let directory: URL

    func build() throws -> PersistentPlaybackAssembly {
        PersistentPlaybackAssembly(
            session: GaplessPlaybackSession(sampleRate: GaplessRenderFormat.sampleRate),
            backend: GaplessRealTimeBackend(),
            preparer: GaplessTrackPreparer(
                provider: GaplessLocalFileProvider(filesByTrackID: files),
                renderSampleRate: GaplessRenderFormat.sampleRate),
            cacheDirectory: directory)
    }
}
