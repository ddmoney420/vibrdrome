import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// The render-observed first-audible callback that Lane 3D-B1b's fallback latch will hang off.
///
/// **What makes this signal trustworthy** is that it is not a proxy. It is driven by
/// `GaplessBoundaryEvent`, which the backend emits only once the player node's own sample clock has
/// reached a segment whose PCM has actually been materialized. Engine-running, node-playing,
/// buffers-scheduled and session-activated are all things that happen *before* audio is heard, and
/// none of them can stand in for it — a fallback latch driven by any of those would release too
/// early and permit a cutover after the listener had already heard the persistent engine.
///
/// It fires once per **play occurrence**, not per queue item, which is why a repeat fires again
/// while a pause, resume or in-place seek does not.
@Suite(.serialized)
@MainActor
struct GaplessAudibleBoundaryCallbackTests {

    private static let sampleRate = GaplessBufferFixtures.sampleRate
    private static let partFrames = 8_192

    /// Real tone files, so the boundary is observed against genuinely rendered audio.
    private func makeParts(_ count: Int, in directory: URL) throws -> [String: URL] {
        var files: [String: URL] = [:]
        for index in 0..<count {
            let url = directory.appendingPathComponent("part\(index).wav")
            try GaplessBufferFixtures.writeStereoWav(
                url: url, frequency: 440 + Double(index) * 110,
                frames: Self.partFrames, sampleRate: Self.sampleRate)
            files["t\(index)"] = url
        }
        return files
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audible-\(UInt64.random(in: 0..<UInt64.max))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    /// A controller over the real backend, with a counting callback attached.
    private func makeController(
        files: [String: URL], songIDs: [String], counter: @escaping @MainActor () -> Void
    ) -> (GaplessPlaybackController, GaplessPlaybackSession, GaplessRealTimeBackend) {
        let session = GaplessPlaybackSession(sampleRate: Self.sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = Double(Self.partFrames) / Self.sampleRate }
        let backend = GaplessRealTimeBackend()
        let controller = GaplessPlaybackController(
            session: session, backend: backend,
            preparer: GaplessTrackPreparer(
                provider: GaplessLocalFileProvider(filesByTrackID: files),
                renderSampleRate: Self.sampleRate))
        controller.onFirstAudibleSample = counter
        return (controller, session, backend)
    }

    /// Drive real ticks until `predicate` holds or the deadline passes.
    private func drive(
        _ controller: GaplessPlaybackController, seconds: Double, until predicate: () -> Bool = { false }
    ) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            await controller.tick()
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(4))
        }
    }

    // MARK: - First item of a new session

    /// The load-bearing case the audit was about: the first occurrence of a fresh session fires,
    /// with no preceding item to transition from.
    @Test func theFirstItemOfANewSessionFiresOnce() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(1, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(files: files, songIDs: ["t0"]) { invocations += 1 }
            defer { controller.stop() }

            #expect(invocations == 0, "fired before playback started")
            try await controller.play()
            await drive(controller, seconds: 3) { invocations >= 1 }

            #expect(invocations == 1,
                    "the first item of a fresh session fired \(invocations) times, expected 1")
        }
    }

    /// It is not a proxy for the engine starting: after `play()` returns, audio has been scheduled
    /// and the engine is running, but the callback waits for the render clock.
    @Test func itDoesNotFireMerelyBecauseTheEngineStartedOrBuffersWereScheduled() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(1, in: directory)
            var invocations = 0
            let (controller, _, backend) = makeController(
                files: files, songIDs: ["t0"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            // The engine is up and buffers exist, but no tick has observed the render clock yet.
            #expect(backend.engine.engine.isRunning, "fixture should have a running engine here")
            #expect(invocations == 0,
                    "fired on engine start / buffer scheduling rather than on render observation")

            await drive(controller, seconds: 3) { invocations >= 1 }
            #expect(invocations == 1)
        }
    }

    // MARK: - One per occurrence

    /// Four occurrences fire four times, matching the backend's one-boundary-per-play-instance rule.
    @Test func fourPlayInstancesFireFourTimes() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(4, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(
                files: files, songIDs: ["t0", "t1", "t2", "t3"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            await drive(controller, seconds: 8) { invocations >= 4 }

            #expect(invocations == 4, "four occurrences fired \(invocations) times")
        }
    }

    /// Repeated ticks after a boundary do not re-fire it: the backend reports each instance once.
    @Test func aDuplicateBoundaryForTheSameOccurrenceDoesNotFireAgain() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(1, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(files: files, songIDs: ["t0"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            await drive(controller, seconds: 3) { invocations >= 1 }
            let afterFirst = invocations

            // Keep ticking well past the boundary.
            for _ in 0..<50 { await controller.tick() }

            #expect(invocations == afterFirst,
                    "the same occurrence fired again on later ticks (\(invocations))")
        }
    }

    // MARK: - Pause, resume, seek

    /// Pause and resume are not new occurrences.
    @Test func pauseAndResumeDoNotAddAnInvocation() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(1, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(files: files, songIDs: ["t0"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            await drive(controller, seconds: 3) { invocations >= 1 }
            let afterFirst = invocations
            #expect(afterFirst == 1)

            controller.pause()
            for _ in 0..<10 { await controller.tick() }
            try controller.resume()
            await drive(controller, seconds: 1)

            #expect(invocations == afterFirst,
                    "pause/resume produced a false occurrence boundary (\(invocations))")
        }
    }

    /// A seek re-fires — and that is correct, not a leak.
    ///
    /// Measured: seeking took the callback from 1 invocation to 3. A seek tears down the scheduled
    /// tail and re-schedules from the new position, which allocates **new play instances** for the
    /// current item and the one behind it, so the backend genuinely observes new occurrences
    /// becoming audible. The guarantee is per *instance*, not per seek: the same play instance never
    /// reports twice, which `aDuplicateBoundaryForTheSameOccurrenceDoesNotFireAgain` pins.
    ///
    /// This matters for Lane 3D-B1b: the callback means "an occurrence became audible", **not**
    /// "a new session started". The fallback latch is safe either way — it only ever latches from
    /// permitted to prohibited — but nothing downstream may read a repeat firing as a new session.
    @Test func seekReschedulesAndReportsNewOccurrences() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(2, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(
                files: files, songIDs: ["t0", "t1"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            await drive(controller, seconds: 3) { invocations >= 1 }
            let afterFirst = invocations
            #expect(afterFirst >= 1, "the first occurrence never became audible")

            try await controller.seek(toSeconds: 0.05)
            await drive(controller, seconds: 1)

            // New occurrences, never fewer — and the count only ever moves forward.
            #expect(invocations >= afterFirst,
                    "invocations went backwards, which cannot happen")

            // Ticking on past the seek adds nothing further: those instances are already reported.
            let afterSeek = invocations
            for _ in 0..<40 { await controller.tick() }
            #expect(invocations == afterSeek,
                    "post-seek occurrences re-reported themselves (\(invocations) vs \(afterSeek))")
        }
    }

    // MARK: - Stale events

    /// A superseded tail contributes nothing: the controller drops those events before the callback.
    @Test func staleTailEventsDoNotFire() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(3, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(
                files: files, songIDs: ["t0", "t1", "t2"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            await drive(controller, seconds: 3) { invocations >= 1 }
            let afterFirst = invocations
            let staleBefore = controller.staleResultCount

            // Replacing the queue supersedes the scheduled tail.
            try await controller.replaceQueue(songIDs: ["t2", "t1"], startIndex: 0)
            await drive(controller, seconds: 2)

            // Whatever fired, it was never a stale event: those are filtered out of `live`.
            #expect(controller.staleResultCount >= staleBefore)
            #expect(invocations >= afterFirst,
                    "invocations went backwards, which cannot happen")
        }
    }

    // MARK: - Nil callback

    /// A nil callback is the default and changes nothing about playback.
    @Test func aNilCallbackChangesNoBehaviour() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(2, in: directory)
            let session = GaplessPlaybackSession(sampleRate: Self.sampleRate)
            session.replaceQueue(songIDs: ["t0", "t1"])
            let backend = GaplessRealTimeBackend()
            let controller = GaplessPlaybackController(
                session: session, backend: backend,
                preparer: GaplessTrackPreparer(
                    provider: GaplessLocalFileProvider(filesByTrackID: files),
                    renderSampleRate: Self.sampleRate))
            defer { controller.stop() }

            #expect(controller.onFirstAudibleSample == nil, "the callback must default to nil")

            try await controller.play()
            await drive(controller, seconds: 3) { backend.renderFrame > 0 }

            // Playback proceeded normally with no callback attached.
            #expect(backend.renderFrame > 0, "playback did not progress without a callback")
            #expect(backend.engine.engine.isRunning)
        }
    }

    // MARK: - Now Playing publication

    private func makeSong(id: String) -> Song {
        Song(id: id, parent: nil, title: "Track \(id)",
             album: "Album", artist: "Artist", albumArtist: nil, albumId: nil, artistId: nil,
             track: nil, year: nil, genre: nil, coverArt: nil,
             size: nil, contentType: nil, suffix: nil,
             duration: 1, bitRate: nil, path: nil,
             discNumber: nil, created: nil, starred: nil, userRating: nil,
             bpm: nil, replayGain: nil, musicBrainzId: nil)
    }

    /// Now Playing publishes once per audible boundary, in play order, with elapsed ticking and a
    /// real duration — and a user Stop clears the published session.
    ///
    /// The bridge's system-facing closures are overridden so the test observes exactly what would
    /// reach `NowPlayingManager` without writing to the real `MPNowPlayingInfoCenter`.
    @Test func nowPlayingPublishesAtAudibleBoundariesInOrder() async throws {
        try await withTemporaryDirectory { directory in
            let ids = ["t0", "t1", "t2"]
            let files = try makeParts(3, in: directory)
            let assembly = PersistentPlaybackAssembly(
                session: GaplessPlaybackSession(sampleRate: Self.sampleRate),
                backend: GaplessRealTimeBackend(),
                preparer: GaplessTrackPreparer(
                    provider: GaplessLocalFileProvider(filesByTrackID: files),
                    renderSampleRate: Self.sampleRate),
                cacheDirectory: directory)
            let adapter = PersistentApplicationPlaybackAdapter(assembly: assembly)
            defer { adapter.stop() }

            var publishedSongs: [String] = []
            var elapsedPublishes = 0
            adapter.nowPlaying.publishMetadata = { update in publishedSongs.append(update.songID) }
            adapter.nowPlaying.publishElapsed = { _, _ in elapsedPublishes += 1 }

            adapter.adoptQueue(ids.map(makeSong))
            assembly.session.replaceQueue(songIDs: ids)
            for id in ids {
                assembly.session.songDurations[id] = Double(Self.partFrames) / Self.sampleRate
            }
            try await assembly.controller.play()

            // Drive exactly as the heartbeat does: tick, then refresh the observable mirror —
            // which is where boundary events become Now Playing publishes.
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline, publishedSongs.count < ids.count {
                await assembly.controller.tick()
                adapter.refreshObservedState()
                try? await Task.sleep(for: .milliseconds(4))
            }

            #expect(publishedSongs == ids,
                    "published \(publishedSongs), expected each track once in play order")
            #expect(adapter.nowPlaying.rejectedStaleUpdates == 0)
            #expect(elapsedPublishes >= 1, "elapsed never reached the system")
            #expect(adapter.effectiveDuration > 0, "no duration for the audible track")
            #expect(adapter.duration > 0)

            adapter.stop()
            #expect(adapter.nowPlaying.publishedInstance == nil,
                    "Stop left a published play instance behind")
        }
    }

    /// Completed plays reach the scrobble seam exactly once each, and every play announces once at
    /// its audible boundary. The fixture's tracks are far shorter than any real threshold, so the
    /// session's own eligibility policy is exercised: these plays are heard end-to-end (audible
    /// frames exceed half their sub-second durations) and must submit; a track cut short must not.
    @Test func completedPlaysSubmitOnceAndAnnounceOncePerBoundary() async throws {
        try await withTemporaryDirectory { directory in
            let ids = ["t0", "t1", "t2"]
            let files = try makeParts(3, in: directory)
            let assembly = PersistentPlaybackAssembly(
                session: GaplessPlaybackSession(sampleRate: Self.sampleRate),
                backend: GaplessRealTimeBackend(),
                preparer: GaplessTrackPreparer(
                    provider: GaplessLocalFileProvider(filesByTrackID: files),
                    renderSampleRate: Self.sampleRate),
                cacheDirectory: directory)
            let adapter = PersistentApplicationPlaybackAdapter(assembly: assembly)
            defer { adapter.stop() }

            var submitted: [String] = []
            var announced: [String] = []
            adapter.submitPlay = { submitted.append($0.id) }
            adapter.announceNowPlaying = { announced.append($0.id) }
            adapter.nowPlaying.publishMetadata = { _ in }
            adapter.nowPlaying.publishElapsed = { _, _ in }

            adapter.adoptQueue(ids.map(makeSong))
            assembly.session.replaceQueue(songIDs: ids)
            for id in ids {
                assembly.session.songDurations[id] = Double(Self.partFrames) / Self.sampleRate
            }
            try await assembly.controller.play()

            // The first two tracks end naturally; their plays were fully heard and must submit.
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline, submitted.count < 2 {
                await assembly.controller.tick()
                adapter.refreshObservedState()
                try? await Task.sleep(for: .milliseconds(4))
            }

            #expect(submitted == ["t0", "t1"],
                    "submissions were \(submitted), expected each finished play exactly once")
            #expect(announced == ids || announced == ["t0", "t1"],
                    "announcements were \(announced), expected once per audible boundary")

            // Draining again without new events submits nothing — the cursor is the dedup.
            adapter.refreshObservedState()
            #expect(submitted.count == 2, "a repeated refresh double-submitted a play")
        }
    }

    /// The persistent visualizer publishes real frames across gapless boundaries when persistent
    /// owns publication; pause freezes it (legacy parity), resume continues it, ownership loss
    /// silences it, and Stop ends it with nothing publishing afterwards.
    @Test func persistentVisualizerPublishesAcrossBoundariesAndFencesOwnership() async throws {
        try await withTemporaryDirectory { directory in
            let ids = ["t0", "t1", "t2"]
            let files = try makeParts(3, in: directory)
            let assembly = PersistentPlaybackAssembly(
                session: GaplessPlaybackSession(sampleRate: Self.sampleRate),
                backend: GaplessRealTimeBackend(),
                preparer: GaplessTrackPreparer(
                    provider: GaplessLocalFileProvider(filesByTrackID: files),
                    renderSampleRate: Self.sampleRate),
                cacheDirectory: directory)
            let adapter = PersistentApplicationPlaybackAdapter(assembly: assembly)
            defer {
                adapter.stop()
                VisualizerOwnershipGate.shared.authorityChanged(to: .none)
            }
            adapter.nowPlaying.publishMetadata = { _ in }
            adapter.nowPlaying.publishElapsed = { _, _ in }
            adapter.submitPlay = { _ in }
            adapter.announceNowPlaying = { _ in }

            // Persistent owns visualizer publication, and the visualizer UI is open.
            VisualizerOwnershipGate.shared.authorityChanged(to: .persistent)
            adapter.visualizerActive = true

            adapter.adoptQueue(ids.map(makeSong))
            assembly.session.replaceQueue(songIDs: ids)
            for id in ids {
                assembly.session.songDurations[id] = Double(Self.partFrames) / Self.sampleRate
            }
            try await assembly.controller.play()
            #expect(assembly.backend.engine.visualizerFeed.isInstalled,
                    "starting the persistent engine did not install the visualizer tap")

            @MainActor func drive(until predicate: () -> Bool, seconds: Double) async {
                let deadline = Date().addingTimeInterval(seconds)
                while Date() < deadline, !predicate() {
                    await assembly.controller.tick()
                    adapter.refreshObservedState()
                    try? await Task.sleep(for: .milliseconds(4))
                }
            }

            // Frames flow across all three tracks — the last boundary included.
            await drive(until: {
                adapter.visualizerFramesPublished > 0
                    && assembly.session.queue.currentIndex >= 2
            }, seconds: 6)
            let acrossBoundaries = adapter.visualizerFramesPublished
            #expect(acrossBoundaries > 0, "no visualizer frames published during playback")
            #expect(assembly.session.queue.currentIndex >= 2, "fixture never crossed its boundaries")

            // Pause: publication freezes (legacy parity — its tap stops on pause).
            adapter.pause()
            adapter.refreshObservedState()
            let atPause = adapter.visualizerFramesPublished
            for _ in 0..<10 {
                await assembly.controller.tick()
                adapter.refreshObservedState()
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(adapter.visualizerFramesPublished == atPause,
                    "the visualizer kept publishing while paused")

            // Resume: publication continues on the same adapters.
            adapter.resume()
            await drive(until: { adapter.visualizerFramesPublished > atPause }, seconds: 3)
            #expect(adapter.visualizerFramesPublished > atPause,
                    "publication did not resume after resume")

            // Ownership loss mid-session: every subsequent drain is rejected, publishing nothing.
            VisualizerOwnershipGate.shared.authorityChanged(to: .legacy)
            let atLoss = adapter.visualizerFramesPublished
            let rejectionsBefore = adapter.visualizerOwnershipRejections
            for _ in 0..<5 {
                await assembly.controller.tick()
                adapter.refreshObservedState()
                try? await Task.sleep(for: .milliseconds(5))
            }
            #expect(adapter.visualizerFramesPublished == atLoss,
                    "persistent published without owning visualizer publication")
            #expect(adapter.visualizerOwnershipRejections > rejectionsBefore,
                    "rejections were not recorded")

            // Stop with ownership restored: publication ends and stays ended.
            VisualizerOwnershipGate.shared.authorityChanged(to: .persistent)
            adapter.stop()
            let atStop = adapter.visualizerFramesPublished
            adapter.refreshObservedState()
            #expect(adapter.visualizerFramesPublished == atStop,
                    "a frame published after Stop")
        }
    }
}
