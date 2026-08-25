import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Legacy transport must stay down while the persistent backend owns audio.
///
/// **Why this is not a Now Playing concern.** Several production paths reach legacy transport
/// without passing the router — scene activation and CarPlay connection through `restorePlayQueue`,
/// the audio-interruption handler, the sleep timer, and predownload completion. Two of them rebuild
/// an `AVPlayerItem` and re-arm the observers, which puts a **second live transport** underneath an
/// audible persistent session: the two-owner state the whole ownership model exists to prevent. The
/// device smoke test would not have caught it, because nobody backgrounded the app mid-session.
///
/// Every test here establishes its own state and restores it, and asserts on items and observers
/// rather than on the playing flag — a paused `AVQueuePlayer` still holds both.
@Suite(.serialized)
@MainActor
struct LegacyTransportReEntryTests {

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

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reentry-\(UInt64.random(in: 0..<UInt64.max))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func makeFiles(_ ids: [String], in directory: URL) throws -> [String: URL] {
        var files: [String: URL] = [:]
        for (index, id) in ids.enumerated() {
            let url = directory.appendingPathComponent("\(id).wav")
            try GaplessBufferFixtures.writeStereoWav(
                url: url, frequency: 330 + Double(index) * 110,
                frames: Self.trackFrames, sampleRate: Self.sampleRate)
            files[id] = url
        }
        return files
    }

    /// Establish the state these tests need and restore everything afterwards, including the shared
    /// engine's admission latch — a test that left legacy quiesced would silently disable legacy
    /// transport for every suite that followed.
    private func withCleanState(flag: Bool, _ body: () async throws -> Void) async rethrows {
        let engine = AudioEngine.shared
        let flagBefore = PersistentRoutingSetting.isEnabled
        let admissionBefore = engine.isQuiescedForPersistentSession
        let repeatBefore = engine.repeatMode
        let shuffleBefore = engine.shuffleEnabled
        let queueBefore = engine.queue
        let indexBefore = engine.currentIndex
        defer {
            PersistentRoutingSetting.setEnabled(flagBefore)
            engine.isQuiescedForPersistentSession = admissionBefore
            engine.repeatMode = repeatBefore
            engine.shuffleEnabled = shuffleBefore
            engine.queue = queueBefore
            engine.currentIndex = indexBefore
        }
        PersistentRoutingSetting.setEnabled(flag)
        engine.repeatMode = .off
        engine.shuffleEnabled = false
        try await body()
    }

    private func makeRouter(files: [String: URL], directory: URL)
        -> (ApplicationPlaybackRouter, PlaybackSpy) {
        let legacy = PlaybackSpy()
        return (ApplicationPlaybackRouter(
            legacy: legacy,
            persistentBuilder: LocalFileAssemblyBuilder(files: files, directory: directory)), legacy)
    }

    /// Assert the legacy engine is holding nothing that could become audible.
    private func expectLegacyFullyQuiescent(_ engine: AudioEngine, _ note: String) {
        let state = engine.legacyTransportState
        #expect(state.rate == 0, "\(note): legacy rate was \(state.rate)")
        #expect(state.hasCurrentItem == false, "\(note): legacy holds a current AVPlayerItem")
        #expect(state.queuedItemCount == 0,
                "\(note): legacy holds \(state.queuedItemCount) queued items")
        #expect(state.isTransportActive == false, "\(note): legacy transport is active")
    }

    // MARK: - The admission latch

    /// Quiescence closes the latch; only an explicit new legacy session opens it.
    @Test func quiescenceClosesAdmissionAndOnlyPlayReopensIt() async {
        await withCleanState(flag: false) {
            let engine = AudioEngine.shared
            engine.isQuiescedForPersistentSession = false
            #expect(engine.admitsTransportRebuild, "a fresh engine should admit transport")

            engine.quiesceForPersistentSession()
            #expect(engine.admitsTransportRebuild == false,
                    "quiescence left legacy free to rebuild transport")

            // Stop must NOT re-admit: stopping during a persistent session cannot arm legacy to
            // rebuild behind it.
            engine.stop()
            #expect(engine.admitsTransportRebuild == false,
                    "stop re-admitted legacy transport during a handover")

            engine.admitTransportForNewLegacySession()
            #expect(engine.admitsTransportRebuild, "an explicit new legacy session was refused")
        }
    }

    /// A refused rebuild creates no item and attaches no observers.
    @Test func aRefusedRebuildCreatesNoItemAndNoObservers() async throws {
        try await withTemporaryDirectory { directory in
            await withCleanState(flag: false) {
                let engine = AudioEngine.shared
                engine.quiesceForPersistentSession()
                let url = directory.appendingPathComponent("probe.wav")
                try? GaplessBufferFixtures.writeStereoWav(
                    url: url, frequency: 440, frames: Self.trackFrames,
                    sampleRate: Self.sampleRate)

                engine.replacePlayerItem(with: url)
                engine.prepareLookahead()

                expectLegacyFullyQuiescent(engine, "after a refused rebuild")
            }
        }
    }

    // MARK: - The regression this checkpoint exists for

    /// Persistent playing → app resigns active → app becomes active → persistent is still the sole
    /// transport owner.
    ///
    /// This is the scenario that was live on the device build: scene activation calls
    /// `restorePlayQueue`, which preloads the current song, replaces the player item and re-arms the
    /// observers. It fails if `restorePlayQueue` is allowed to resurrect the `AVQueuePlayer`.
    @Test func backgroundThenForegroundLeavesPersistentTheSoleOwner() async throws {
        try await withTemporaryDirectory { directory in
            try await withCleanState(flag: true) {
                let files = try makeFiles(["s0", "s1"], in: directory)
                let (router, legacySpy) = makeRouter(files: files, directory: directory)
                let engine = AudioEngine.shared
                let songs = ["s0", "s1"].map { makeSong(id: $0) }

                router.play(song: songs[0], from: songs, at: 0)
                await router.awaitPendingSelectionForTesting()
                #expect(router.ownership.authority == .persistent,
                        "the fixture settled as \(router.sessionSelectionState.describedForDiagnostics)")
                let indexBefore = router.currentIndex
                let heartbeatStartsBefore = router.diagnostics.heartbeat.startCount

                // The lifecycle sequence a real backgrounding produces.
                engine.saveQueueLocally()
                engine.restorePlayQueue(client: SubsonicClient(
                    baseURL: URL(string: "https://example.invalid")!,
                    username: "probe", password: "probe"))
                engine.preloadCurrentSong()
                engine.prepareLookahead()

                expectLegacyFullyQuiescent(engine, "after background/foreground")
                #expect(router.ownership.authority == .persistent,
                        "lifecycle activity moved playback authority")
                #expect(router.ownership.ownerCount == 1)
                #expect(router.isPersistentSessionActive)
                #expect(router.currentIndex == indexBefore,
                        "lifecycle activity moved the persistent queue position")
                #expect(router.diagnostics.heartbeat.startCount == heartbeatStartsBefore,
                        "lifecycle activity started a second heartbeat")
                #expect(router.diagnostics.heartbeat.isRunning,
                        "lifecycle activity killed the persistent heartbeat")
                #expect(legacySpy.playCalls.isEmpty, "lifecycle activity started legacy transport")
                await router.releaseSessionForTesting()
            }
        }
    }

    /// CarPlay connection runs the same restoration path, so it gets the same guarantee.
    @Test func carPlayConnectionCreatesNoLegacyTransport() async throws {
        try await withTemporaryDirectory { directory in
            try await withCleanState(flag: true) {
                let files = try makeFiles(["c0"], in: directory)
                let (router, legacySpy) = makeRouter(files: files, directory: directory)
                let engine = AudioEngine.shared
                let song = makeSong(id: "c0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()
                #expect(router.ownership.authority == .persistent)

                // What CarPlay scene connection actually runs.
                _ = CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(
                    client: SubsonicClient(baseURL: URL(string: "https://example.invalid")!,
                                           username: "probe", password: "probe"))
                engine.preloadCurrentSong()

                expectLegacyFullyQuiescent(engine, "after a CarPlay connect")
                #expect(router.ownership.authority == .persistent)
                #expect(legacySpy.playCalls.isEmpty)
                await router.releaseSessionForTesting()
            }
        }
    }

    /// Predownload completion calls `prepareLookahead` directly; it must not build a lookahead item.
    @Test func predownloadLookaheadIsRefusedDuringAPersistentSession() async throws {
        try await withTemporaryDirectory { directory in
            try await withCleanState(flag: true) {
                let files = try makeFiles(["p0", "p1"], in: directory)
                let (router, _) = makeRouter(files: files, directory: directory)
                let engine = AudioEngine.shared
                let songs = ["p0", "p1"].map { makeSong(id: $0) }

                router.play(song: songs[0], from: songs, at: 0)
                await router.awaitPendingSelectionForTesting()
                #expect(router.ownership.authority == .persistent)

                for _ in 0..<5 { engine.prepareLookahead() }

                expectLegacyFullyQuiescent(engine, "after repeated lookahead attempts")
                await router.releaseSessionForTesting()
            }
        }
    }

    // MARK: - Interruption and sleep timer route by authority

    /// An interruption pauses whichever backend owns the session.
    @Test func interruptionPauseAndResumeRouteToPersistent() async throws {
        try await withTemporaryDirectory { directory in
            try await withCleanState(flag: true) {
                let files = try makeFiles(["i0"], in: directory)
                let (router, legacySpy) = makeRouter(files: files, directory: directory)
                let song = makeSong(id: "i0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()
                guard let assembly = router.persistentAssembly else {
                    Issue.record("no assembly")
                    // The now-async release cannot live in a defer; this exit must still clean up.
                    await router.releaseSessionForTesting()
                    return
                }
                let heartbeatStarts = router.diagnostics.heartbeat.startCount

                // Point the production interruption handler at this router, then drive exactly
                // what it does on `.began` / `.ended`.
                AudioSessionManager.playbackOverrideForTesting = router
                defer { AudioSessionManager.playbackOverrideForTesting = nil }
                AudioSessionManager.playback.pause()
                #expect(assembly.backend.state == .paused,
                        "an interruption did not pause the persistent backend (\(assembly.backend.state))")

                AudioSessionManager.playback.resume()
                #expect(assembly.backend.state == .playing,
                        "an interruption resume did not restart persistent")

                // Resume continues the session rather than starting a new one.
                #expect(router.diagnostics.heartbeat.startCount == heartbeatStarts,
                        "resume created a second session")
                #expect(router.pendingPlanningGeneration == 1,
                        "resume re-ran selection")
                #expect(legacySpy.calls.contains("pause") == false,
                        "the interruption reached the quiesced legacy engine")
                #expect(legacySpy.calls.contains("resume") == false)
                await router.releaseSessionForTesting()
            }
        }
    }

    /// The sleep timer's fade and pause both land on the owning backend.
    @Test func sleepTimerPauseRoutesToPersistent() async throws {
        try await withTemporaryDirectory { directory in
            try await withCleanState(flag: true) {
                let files = try makeFiles(["t0"], in: directory)
                let (router, legacySpy) = makeRouter(files: files, directory: directory)
                let song = makeSong(id: "t0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()
                guard let assembly = router.persistentAssembly else {
                    Issue.record("no assembly")
                    await router.releaseSessionForTesting()
                    return
                }

                // Point the production sleep timer at this router, then drive exactly what
                // `expire()` does.
                SleepTimer.shared.playbackOverrideForTesting = router
                defer { SleepTimer.shared.playbackOverrideForTesting = nil }
                SleepTimer.shared.playback.applyEffectiveVolume()
                SleepTimer.shared.playback.pause()

                #expect(assembly.backend.state == .paused,
                        "the sleep timer did not pause persistent")
                #expect(legacySpy.calls.contains("pause") == false,
                        "the sleep timer paused the quiesced legacy engine")
                await router.releaseSessionForTesting()
            }
        }
    }

    /// The sleep-timer fade reaches the persistent output, rather than cutting it dead.
    @Test func theSleepTimerFadeAppliesToPersistentOutput() async throws {
        try await withTemporaryDirectory { directory in
            try await withCleanState(flag: true) {
                let files = try makeFiles(["f0"], in: directory)
                let (router, _) = makeRouter(files: files, directory: directory)
                let fadeBefore = SleepTimer.shared.fadeFactor
                defer {
                    SleepTimer.shared.fadeFactor = fadeBefore
                    SleepTimer.shared.playbackOverrideForTesting = nil
                }
                let song = makeSong(id: "f0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()
                guard let assembly = router.persistentAssembly else {
                    Issue.record("no assembly")
                    await router.releaseSessionForTesting()
                    return
                }
                SleepTimer.shared.playbackOverrideForTesting = router
                router.userVolume = 1

                SleepTimer.shared.fadeFactor = 0.25
                SleepTimer.shared.playback.applyEffectiveVolume()

                #expect(abs(assembly.backend.engine.player.volume - 0.25) < 0.001,
                        "the fade reached \(assembly.backend.engine.player.volume), expected 0.25")
                // And the user's setting is not consumed by the fade — applying twice must not
                // compound.
                SleepTimer.shared.playback.applyEffectiveVolume()
                #expect(abs(assembly.backend.engine.player.volume - 0.25) < 0.001,
                        "the fade compounded on a second apply")
                #expect(router.userVolume == 1,
                        "the fade overwrote the user's volume setting")
                await router.releaseSessionForTesting()
            }
        }
    }

    // MARK: - Mirror cases: legacy behaviour is unchanged

    /// With no persistent session, legacy transport rebuilds exactly as before.
    @Test func legacyTransportStillRebuildsWhenLegacyOwnsPlayback() async throws {
        try await withTemporaryDirectory { directory in
            await withCleanState(flag: false) {
                let engine = AudioEngine.shared
                engine.quiesceForPersistentSession()
                #expect(engine.admitsTransportRebuild == false)

                // A new legacy session re-admits transport — this is the path the router uses for a
                // legacy plan, a pre-audible fallback and radio.
                engine.admitTransportForNewLegacySession()

                let url = directory.appendingPathComponent("legacy.wav")
                try? GaplessBufferFixtures.writeStereoWav(
                    url: url, frequency: 440, frames: Self.trackFrames, sampleRate: Self.sampleRate)
                engine.replacePlayerItem(with: url)

                #expect(engine.legacyTransportState.hasCurrentItem,
                        "legacy could not rebuild transport for its own session")
                engine.quiesceForPersistentSession()
                expectLegacyFullyQuiescent(engine, "cleanup")
            }
        }
    }

    /// Flag Off is unchanged: a legacy play admits transport and reaches the legacy backend.
    @Test func flagOffBehaviourIsUnchanged() async throws {
        try await withTemporaryDirectory { directory in
            try await withCleanState(flag: false) {
                let files = try makeFiles(["l0"], in: directory)
                let (router, legacySpy) = makeRouter(files: files, directory: directory)
                let engine = AudioEngine.shared
                engine.quiesceForPersistentSession()
                let song = makeSong(id: "l0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()

                #expect(legacySpy.playCalls.count == 1, "flag Off did not start legacy")
                #expect(router.ownership.authority != .persistent)
                #expect(router.diagnostics.heartbeat.startCount == 0,
                        "flag Off started a persistent heartbeat")
                await router.releaseSessionForTesting()
            }
        }
    }

    /// Interruption pause/resume still reach legacy when legacy owns the session.
    @Test func interruptionStillRoutesToLegacyUnderLegacyAuthority() async throws {
        try await withTemporaryDirectory { directory in
            try await withCleanState(flag: false) {
                let files = try makeFiles(["m0"], in: directory)
                let (router, legacySpy) = makeRouter(files: files, directory: directory)
                let song = makeSong(id: "m0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()
                legacySpy.resetForTesting()

                router.pause()
                router.resume()

                #expect(legacySpy.calls.filter { $0 == "pause" }.count == 1,
                        "legacy stopped receiving its own interruption pause")
                #expect(legacySpy.calls.filter { $0 == "resume" }.count == 1)
                await router.releaseSessionForTesting()
            }
        }
    }

    // MARK: - Isolation

    /// This suite leaves both transports down and the admission latch as it found it.
    @Test func teardownLeavesNothingRunning() async throws {
        try await withTemporaryDirectory { directory in
            try await withCleanState(flag: true) {
                let files = try makeFiles(["z0"], in: directory)
                let (router, _) = makeRouter(files: files, directory: directory)
                let song = makeSong(id: "z0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()
                #expect(router.ownership.authority == .persistent)

                await router.releaseSessionForTesting()

                #expect(router.ownership.authority == PlaybackAuthority.none)
                #expect(router.diagnostics.heartbeat.isRunning == false)
                if let assembly = router.persistentAssembly {
                    // Post-teardown truth: settle the ordered teardown, then read the domain live.
                    await assembly.backend.settleTransport()
                    let snapshot = await assembly.backend.domainSnapshotForTesting
                    #expect(assembly.backend.state == .idle)
                    #expect(assembly.backend.engine.engine.isRunning == false)
                    #expect(snapshot.poolInFlight == 0)
                }
                AudioEngine.shared.quiesceForPersistentSession()
                expectLegacyFullyQuiescent(AudioEngine.shared, "suite teardown")
            }
        }
    }
}
