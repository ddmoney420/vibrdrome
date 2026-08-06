import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// The production heartbeat that drives `GaplessPlaybackController.tick()` while persistent owns
/// audio.
///
/// **Why this exists at all.** Buffer refill is already self-sustaining — the recycle inbox signals
/// `pump()` as the node finishes with each buffer — so a persistent session without a heartbeat
/// plays its first track and then stops: nothing observes the render clock, no boundary is drained,
/// the session index never advances, and the prefetch window is never topped up. Everything below
/// goes through the real application path, and **nothing here calls `tick()` directly**: if the
/// production heartbeat were deleted, the advancement tests would fail rather than quietly keep
/// passing on a test-driven pump.
@Suite(.serialized)
@MainActor
struct PersistentHeartbeatTests {

    private static let sampleRate = GaplessBufferFixtures.sampleRate
    /// Short enough that three of them transition inside a test's patience, long enough that the
    /// 50 ms heartbeat observes each boundary rather than racing past it.
    private static let trackFrames = 22_050

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
            .appendingPathComponent("beat-\(UInt64.random(in: 0..<UInt64.max))", isDirectory: true)
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

    /// A router over a real assembly and real media — the whole production path, with only the
    /// legacy transport substituted so no real server playback is attempted.
    private func makeProductionRouter(files: [String: URL], directory: URL)
        -> (ApplicationPlaybackRouter, PlaybackSpy) {
        let legacy = PlaybackSpy()
        let router = ApplicationPlaybackRouter(
            legacy: legacy,
            persistentBuilder: LocalFileAssemblyBuilder(files: files, directory: directory))
        return (router, legacy)
    }

    /// Establish the initial state these tests require, explicitly, and restore it afterwards.
    ///
    /// **Repeat and shuffle are the load-bearing part.** The session snapshot carries them from
    /// `AudioEngine.shared`, which is process-wide: with Repeat One left on by another suite, the
    /// persistent session correctly plans the same occurrence over and over, the index never
    /// advances, and an advancement test fails for a reason that has nothing to do with the
    /// heartbeat. These tests are about automatic progression, so progression is what the fixture
    /// has to establish.
    private func withRoutingFlag(_ enabled: Bool, _ body: () async throws -> Void) async rethrows {
        let engine = AudioEngine.shared
        let flagBefore = PersistentRoutingSetting.isEnabled
        let repeatBefore = engine.repeatMode
        let shuffleBefore = engine.shuffleEnabled
        defer {
            PersistentRoutingSetting.setEnabled(flagBefore)
            engine.repeatMode = repeatBefore
            engine.shuffleEnabled = shuffleBefore
        }
        PersistentRoutingSetting.setEnabled(enabled)
        engine.repeatMode = .off
        engine.shuffleEnabled = false
        try await body()
    }

    /// Wait for a condition **without ticking anything** — the production heartbeat is what has to
    /// make it come true.
    private func waitFor(seconds: Double, until predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func heartbeat(_ router: ApplicationPlaybackRouter) -> PersistentHeartbeatDiagnostics {
        router.diagnostics.heartbeat
    }

    // MARK: - Cadence

    /// The cadence is a stated policy, not an accident.
    @Test func theHeartbeatCadenceIsTheDocumentedInterval() {
        #expect(PersistentPlaybackHeartbeat.interval == .milliseconds(50))
    }

    // MARK: - No heartbeat without a persistent session

    /// Cold launch drives nothing.
    @Test func coldLaunchCreatesNoHeartbeat() {
        let legacy = PlaybackSpy()
        let router = ApplicationPlaybackRouter(legacy: legacy,
                                               persistentBuilder: RefusingAssemblyBuilder())

        let beat = heartbeat(router)
        #expect(beat.isRunning == false)
        #expect(beat.startCount == 0)
        #expect(beat.tickCount == 0)
    }

    /// Flag Off plays legacy and drives nothing.
    @Test func flagOffCreatesNoHeartbeat() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(false) {
                let files = try makeFiles(["t0"], in: directory)
                let (router, legacy) = makeProductionRouter(files: files, directory: directory)
                defer { router.releaseSessionForTesting() }

                router.play(song: makeSong(id: "t0"), from: [makeSong(id: "t0")], at: 0)
                await router.awaitPendingSelectionForTesting()

                #expect(legacy.playCalls.count == 1, "flag Off did not start legacy")
                #expect(heartbeat(router).startCount == 0, "flag Off started a heartbeat")
            }
        }
    }

    /// A legacy-selected session drives nothing.
    @Test func legacySelectionCreatesNoHeartbeat() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                // Six channels: refused after real inspection, so this is a real legacy selection.
                let url = directory.appendingPathComponent("surround.wav")
                try GaplessBufferFixtures.writeWav(
                    url: url, frequency: 440, frames: Self.trackFrames,
                    sampleRate: Self.sampleRate, channelCount: 6)
                let (router, legacy) = makeProductionRouter(files: ["s0": url], directory: directory)
                defer { router.releaseSessionForTesting() }

                router.play(song: makeSong(id: "s0"), from: [makeSong(id: "s0")], at: 0)
                await router.awaitPendingSelectionForTesting()

                #expect(router.ownership.authority == .legacy)
                #expect(legacy.playCalls.count == 1)
                #expect(heartbeat(router).startCount == 0,
                        "a legacy session started a persistent heartbeat")
            }
        }
    }

    /// Planning and assembly construction on their own drive nothing: the assembly is built to
    /// inspect the source, and that must not begin ticking it.
    @Test func planningAloneCreatesNoHeartbeat() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["t0"], in: directory)
                let (router, _) = makeProductionRouter(files: files, directory: directory)
                defer { router.releaseSessionForTesting() }

                let assembly = try router.preparePersistentBackend()
                let planner = PlaybackSessionSelectionPlanner(
                    prepareAssembly: { assembly }, isPersistentRoutingEnabled: { true })
                let plan = await planner.plan(request: PlaybackSessionSelectionRequest(
                    songs: [makeSong(id: "t0")], generation: 1))

                #expect(plan.plannedBackend == .persistent, "the fixture should plan persistent")
                #expect(heartbeat(router).startCount == 0,
                        "planning or construction started a heartbeat")
                #expect(assembly.backend.state == .idle,
                        "planning started the backend")
            }
        }
    }

    // MARK: - The advancement proof

    /// Three real tracks advance on their own, driven only by the production heartbeat.
    ///
    /// This is the test that fails if the heartbeat is removed: nothing here ticks the controller,
    /// so every transition below is the production loop's doing.
    @Test func threeTracksAdvanceAutomaticallyOnTheProductionHeartbeat() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let ids = ["a0", "a1", "a2"]
                let files = try makeFiles(ids, in: directory)
                let (router, legacy) = makeProductionRouter(files: files, directory: directory)
                defer { router.releaseSessionForTesting() }
                let songs = ids.map { makeSong(id: $0) }

                router.play(song: songs[0], from: songs, at: 0)
                await router.awaitPendingSelectionForTesting()

                #expect(router.ownership.authority == .persistent,
                        "the session settled as \(router.sessionSelectionState.describedForDiagnostics)")
                #expect(legacy.playCalls.isEmpty, "legacy transport was started")
                guard let assembly = router.persistentAssembly else {
                    Issue.record("no persistent assembly")
                    return
                }
                let beatAfterStart = heartbeat(router)
                #expect(beatAfterStart.isRunning, "the heartbeat did not start with the session")
                #expect(beatAfterStart.startCount == 1,
                        "the heartbeat started \(beatAfterStart.startCount) times")

                // Nothing below ticks: the production loop is what has to make this come true.
                await waitFor(seconds: 15) { assembly.session.queue.currentIndex >= 2 }

                #expect(assembly.session.queue.currentIndex == 2,
                        "the queue reached index \(assembly.session.queue.currentIndex) of 2")
                #expect(heartbeat(router).tickCount > 0, "the heartbeat never ticked")

                // Each occurrence became audible exactly once, in order, with none skipped.
                let observed = assembly.controller.observedBoundaries
                let heardIDs = observed.map(\.songID)
                #expect(heardIDs == ids,
                        "occurrences became audible as \(heardIDs), expected \(ids)")
                let instances = Set(observed.map(\.playInstance))
                #expect(instances.count == observed.count,
                        "an occurrence reported a boundary more than once")
                #expect(router.currentIndex == 2,
                        "the router reported index \(router.currentIndex) during a persistent session")

                // Concurrency invariant, over the whole run.
                #expect(heartbeat(router).peakConcurrentCount <= 1,
                        "\(heartbeat(router).peakConcurrentCount) ticks overlapped")

                // Stop ends the session, the heartbeat, and every resource behind it.
                router.stop()

                let afterStop = heartbeat(router)
                #expect(afterStop.isRunning == false, "the heartbeat outlived Stop")
                #expect(afterStop.cancellationCount >= 1)
                #expect(assembly.backend.scheduledSegments.isEmpty)
                #expect(assembly.backend.bufferScheduler.pool.inFlightCount == 0,
                        "buffers stayed out of the pool after Stop")
                #expect(assembly.backend.bufferScheduler.pool.availableCount
                        == assembly.backend.bufferScheduler.pool.capacity,
                        "the pool did not fully recover after Stop")
                #expect(assembly.backend.bufferScheduler.liveSourceCount == 0,
                        "source files stayed live after Stop")
                #expect(assembly.backend.bufferScheduler.activeConverterCount == 0,
                        "converters stayed live after Stop")
                #expect(assembly.backend.openFileCount == 0)

                // And it really is stopped: the tick count stops moving.
                let ticksAtStop = heartbeat(router).tickCount
                try? await Task.sleep(for: .milliseconds(300))
                #expect(heartbeat(router).tickCount == ticksAtStop,
                        "ticks continued after Stop")
            }
        }
    }

    /// The first item becomes audible on the heartbeat alone, and the ownership latch closes.
    @Test func theFirstItemBecomesAudibleAndLatchesOwnership() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["b0"], in: directory)
                let (router, _) = makeProductionRouter(files: files, directory: directory)
                defer { router.releaseSessionForTesting() }
                let song = makeSong(id: "b0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()

                // Deliberately no "not yet latched" assertion here: the heartbeat starts inside the
                // selection task, so its first tick may legitimately have run already by the time
                // that task completes. What is guaranteed is that only a rendered boundary closes
                // the latch, which `GaplessAudibleBoundaryCallbackTests` pins directly.
                await waitFor(seconds: 10) { router.ownership.audibleBoundaryReached }

                #expect(router.ownership.audibleBoundaryReached,
                        "the audible callback never reached the ownership latch")
                #expect(router.ownership.isFallbackPermitted == false)
                #expect(router.diagnostics.audibleBoundaryReached)
            }
        }
    }

    // MARK: - One session, one heartbeat

    /// Play for a session that is already active does not add a second heartbeat.
    @Test func repeatedPlayDoesNotCreateASecondHeartbeat() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["c0"], in: directory)
                let (router, _) = makeProductionRouter(files: files, directory: directory)
                defer { router.releaseSessionForTesting() }
                let song = makeSong(id: "c0")

                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()
                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()

                let beat = heartbeat(router)
                // Two sessions were requested, so two starts is correct — what must never happen is
                // two loops running at once.
                #expect(beat.isRunning)
                #expect(beat.peakConcurrentCount <= 1,
                        "\(beat.peakConcurrentCount) heartbeats ticked at once")
                #expect(beat.cancellationCount >= 1,
                        "the replaced session's heartbeat was never cancelled")
            }
        }
    }

    /// Pause and resume keep the same single heartbeat, and pausing advances nothing.
    @Test func pauseAndResumeDoNotDuplicateOrAdvance() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["d0", "d1"], in: directory)
                let (router, _) = makeProductionRouter(files: files, directory: directory)
                defer { router.releaseSessionForTesting() }
                let songs = ["d0", "d1"].map { makeSong(id: $0) }

                router.play(song: songs[0], from: songs, at: 0)
                await router.awaitPendingSelectionForTesting()
                guard let assembly = router.persistentAssembly else {
                    Issue.record("no assembly")
                    return
                }
                await waitFor(seconds: 10) { router.ownership.audibleBoundaryReached }
                let startsBefore = heartbeat(router).startCount

                router.pause()
                let indexAtPause = assembly.session.queue.currentIndex
                let boundariesAtPause = assembly.controller.observedBoundaries.count
                // Long enough for many heartbeat intervals to elapse while paused.
                try? await Task.sleep(for: .milliseconds(400))

                #expect(heartbeat(router).startCount == startsBefore,
                        "pausing created another heartbeat")
                #expect(heartbeat(router).isRunning,
                        "pausing cancelled the session's heartbeat")
                #expect(assembly.session.queue.currentIndex == indexAtPause,
                        "the timeline advanced while paused")
                #expect(assembly.controller.observedBoundaries.count == boundariesAtPause,
                        "a boundary was observed while paused")

                router.resume()
                #expect(heartbeat(router).startCount == startsBefore,
                        "resuming created another heartbeat")
                #expect(heartbeat(router).peakConcurrentCount <= 1)

                // The same session continues rather than restarting.
                await waitFor(seconds: 10) { assembly.session.queue.currentIndex >= 1 }
                #expect(assembly.session.queue.currentIndex == 1,
                        "automatic progression did not resume")
                let heard = assembly.controller.observedBoundaries.map(\.songID)
                #expect(heard == ["d0", "d1"], "boundaries after resume were \(heard)")
            }
        }
    }

    // MARK: - Cancellation

    /// Persistent → Persistent replacement cancels the old heartbeat and runs exactly one new one.
    @Test func replacementCancelsTheOldHeartbeat() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["e0", "e1"], in: directory)
                let (router, _) = makeProductionRouter(files: files, directory: directory)
                defer { router.releaseSessionForTesting() }

                router.play(song: makeSong(id: "e0"), from: [makeSong(id: "e0")], at: 0)
                await router.awaitPendingSelectionForTesting()
                let firstGeneration = heartbeat(router).sessionGeneration

                router.play(song: makeSong(id: "e1"), from: [makeSong(id: "e1")], at: 0)
                await router.awaitPendingSelectionForTesting()

                let beat = heartbeat(router)
                #expect(beat.isRunning, "the replacement session has no heartbeat")
                #expect(beat.sessionGeneration != firstGeneration,
                        "the replacement reused the old session generation")
                #expect(beat.cancellationCount >= 1, "the old heartbeat was never cancelled")
                #expect(beat.peakConcurrentCount <= 1,
                        "\(beat.peakConcurrentCount) heartbeats ticked at once during replacement")
            }
        }
    }

    /// Switching to a legacy session cancels it.
    @Test func switchingToLegacyCancelsTheHeartbeat() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["f0"], in: directory)
                let (router, _) = makeProductionRouter(files: files, directory: directory)
                defer { router.releaseSessionForTesting() }

                router.play(song: makeSong(id: "f0"), from: [makeSong(id: "f0")], at: 0)
                await router.awaitPendingSelectionForTesting()
                #expect(heartbeat(router).isRunning)

                router.planOverrideForTesting = { _ in .legacy(reason: .decoderUnavailable) }
                let song = makeSong(id: "legacy")
                router.play(song: song, from: [song], at: 0)
                await router.awaitPendingSelectionForTesting()

                #expect(router.ownership.authority == .legacy)
                #expect(heartbeat(router).isRunning == false,
                        "the heartbeat survived a switch to legacy")
            }
        }
    }

    /// Radio cancels it.
    @Test func radioCancelsTheHeartbeat() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["g0"], in: directory)
                let (router, _) = makeProductionRouter(files: files, directory: directory)
                defer { router.releaseSessionForTesting() }

                router.play(song: makeSong(id: "g0"), from: [makeSong(id: "g0")], at: 0)
                await router.awaitPendingSelectionForTesting()
                #expect(heartbeat(router).isRunning)

                router.startRadio(artistName: "Probe")

                #expect(router.ownership.authority == .legacy)
                #expect(heartbeat(router).isRunning == false,
                        "the heartbeat survived a radio session")
            }
        }
    }

    /// A failed start never starts one, and the pre-audible fallback leaves none running.
    @Test func aFailedStartAndFallbackLeaveNoHeartbeat() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["h0"], in: directory)
                let (router, legacy) = makeProductionRouter(files: files, directory: directory)
                defer { router.releaseSessionForTesting() }
                // Build the assembly first so its start can be made to fail.
                let assembly = try router.preparePersistentBackend()
                assembly.backend.activateAudioSession = { throw CocoaError(.fileNoSuchFile) }

                router.play(song: makeSong(id: "h0"), from: [makeSong(id: "h0")], at: 0)
                await router.awaitPendingSelectionForTesting()

                #expect(router.ownership.authority == .legacy, "the fallback did not happen")
                #expect(legacy.playCalls.count == 1)
                #expect(heartbeat(router).isRunning == false,
                        "a failed start left a heartbeat running")
                #expect(heartbeat(router).startCount == 0,
                        "a heartbeat started for a session that never played")
                // And the backend the fallback reset is idle, with nothing ticking it.
                #expect(assembly.backend.state == .idle)
            }
        }
    }

    // MARK: - Stale generations

    /// A heartbeat from a replaced session does no work, whatever cancellation has got round to.
    ///
    /// Driven directly against the heartbeat rather than through the router, because the thing
    /// under test is the guard itself: the generation is bumped out from under a running loop and
    /// the controller must receive nothing further.
    @Test func aStaleHeartbeatGenerationPerformsNoWork() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["i0"], in: directory)
            let assembly = PersistentPlaybackAssembly(
                session: GaplessPlaybackSession(sampleRate: Self.sampleRate),
                backend: GaplessRealTimeBackend(),
                preparer: GaplessTrackPreparer(
                    provider: GaplessLocalFileProvider(filesByTrackID: files),
                    renderSampleRate: Self.sampleRate),
                cacheDirectory: directory)
            defer { assembly.controller.stop() }
            assembly.session.replaceQueue(songIDs: ["i0"])
            try await assembly.controller.play()

            let beat = PersistentPlaybackHeartbeat()
            beat.start(controller: assembly.controller, generation: 7)
            await waitFor(seconds: 5) { beat.diagnostics.tickCount > 0 }
            #expect(beat.diagnostics.tickCount > 0, "the heartbeat never ran")

            beat.cancel()
            let ticksAtCancel = beat.diagnostics.tickCount
            try? await Task.sleep(for: .milliseconds(300))

            #expect(beat.diagnostics.tickCount == ticksAtCancel,
                    "a cancelled heartbeat kept ticking")
            #expect(beat.diagnostics.isRunning == false)
            #expect(beat.diagnostics.sessionGeneration != 7,
                    "the generation was not moved past the cancelled session")

            // A new session on the same owner runs exactly one loop.
            beat.start(controller: assembly.controller, generation: 8)
            await waitFor(seconds: 5) { beat.diagnostics.tickCount > ticksAtCancel }
            #expect(beat.diagnostics.startCount == 2)
            #expect(beat.diagnostics.peakConcurrentCount <= 1)
            beat.cancel()
        }
    }

    // MARK: - Diagnostics

    /// Diagnostics report the heartbeat, and carry nothing sensitive.
    @Test func diagnosticsReportTheHeartbeat() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["j0"], in: directory)
                let (router, _) = makeProductionRouter(files: files, directory: directory)
                defer { router.releaseSessionForTesting() }

                router.play(song: makeSong(id: "j0"), from: [makeSong(id: "j0")], at: 0)
                await router.awaitPendingSelectionForTesting()
                await waitFor(seconds: 10) { router.diagnostics.heartbeat.tickCount > 0 }

                let summary = router.diagnostics.summary
                #expect(summary.contains("Persistent heartbeat: Running"))
                #expect(summary.contains("Heartbeat session generation: 1"))
                #expect(summary.contains("Heartbeat tick count:"))
                #expect(summary.contains("Last tick age:"))
                #expect(summary.contains("Heartbeat start count: 1"))
                #expect(summary.contains("Heartbeat cancellation count:"))
                #expect(summary.contains("Concurrent heartbeat count: 1")
                        || summary.contains("Concurrent heartbeat count: 0"),
                        "concurrent heartbeat count was not 0 or 1: \(summary)")
                #expect(summary.lowercased().contains("http") == false)
                #expect(summary.lowercased().contains("token") == false)
                #expect(summary.contains(directory.lastPathComponent) == false)

                router.stop()
                #expect(router.diagnostics.summary.contains("Persistent heartbeat: Stopped"))
            }
        }
    }

    // MARK: - Isolation

    /// This suite leaves no heartbeat, no authority and no running transport behind.
    @Test func teardownLeavesZeroHeartbeats() async throws {
        try await withTemporaryDirectory { directory in
            try await withRoutingFlag(true) {
                let files = try makeFiles(["k0"], in: directory)
                let (router, _) = makeProductionRouter(files: files, directory: directory)

                router.play(song: makeSong(id: "k0"), from: [makeSong(id: "k0")], at: 0)
                await router.awaitPendingSelectionForTesting()
                #expect(heartbeat(router).isRunning, "the fixture never started a heartbeat")

                router.releaseSessionForTesting()

                let beat = heartbeat(router)
                #expect(beat.isRunning == false, "teardown left a heartbeat running")
                #expect(router.ownership.authority == PlaybackAuthority.none)
                if let assembly = router.persistentAssembly {
                    #expect(assembly.backend.state == .idle)
                    #expect(assembly.backend.engine.engine.isRunning == false)
                    #expect(assembly.backend.bufferScheduler.pool.inFlightCount == 0)
                }
                // And no tick lands afterwards.
                let ticks = beat.tickCount
                try? await Task.sleep(for: .milliseconds(300))
                #expect(heartbeat(router).tickCount == ticks,
                        "a released session kept ticking")
            }
        }
    }
}
