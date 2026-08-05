import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Recovering `GaplessRealTimeBackend` from a failed start.
///
/// **Why this is a lifecycle bug and not a cleanup detail.** The production persistent assembly is
/// built once and retained for the process lifetime. `stop()` used to decline to act from
/// `.failed`, so a start that threw part way left the backend there permanently: its scheduled
/// buffers stayed on the player node, its source files stayed open, its converters stayed live, its
/// pool tickets stayed out — and because the only legal exit from `.failed` is `.failed -> .idle`,
/// every later persistent session on that same instance threw `illegalTransition` instead of
/// playing.
///
/// These tests drive a real `AVAudioEngine` over real tone files, so "the resources were released"
/// is measured on the actual pool, the actual open-file count and the actual converter count rather
/// than asserted.
@Suite(.serialized)
@MainActor
struct GaplessBackendFailureRecoveryTests {

    private static let sampleRate = GaplessBufferFixtures.sampleRate
    /// Long enough that the source is still live, with buffers in flight, at the moment the start
    /// fails — a fixture that drains before the failure would prove nothing about releasing them.
    private static let trackFrames = 176_400

    // MARK: - Fixtures

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recover-\(UInt64.random(in: 0..<UInt64.max))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    /// Real media. The 48 kHz option exists so the conversion path is genuinely exercised: at the
    /// render rate no converter is built at all, and a converter count that was always zero would
    /// make "converters returned to zero" vacuous.
    private func makeFiles(_ ids: [String], in directory: URL,
                           sampleRate: Double = sampleRate) throws -> [String: URL] {
        var files: [String: URL] = [:]
        for (index, id) in ids.enumerated() {
            let url = directory.appendingPathComponent("\(id).wav")
            try GaplessBufferFixtures.writeWav(
                url: url, frequency: 440 + Double(index) * 110,
                frames: Self.trackFrames, sampleRate: sampleRate, channelCount: 2)
            files[id] = url
        }
        return files
    }

    private func makeAssembly(files: [String: URL], directory: URL) -> PersistentPlaybackAssembly {
        PersistentPlaybackAssembly(
            session: GaplessPlaybackSession(sampleRate: Self.sampleRate),
            backend: GaplessRealTimeBackend(),
            preparer: GaplessTrackPreparer(
                provider: GaplessLocalFileProvider(filesByTrackID: files),
                renderSampleRate: Self.sampleRate),
            cacheDirectory: directory)
    }

    /// Drive a real start that fails at audio-session activation, after real scheduling has already
    /// happened. Returns once the backend is genuinely `.failed`.
    @discardableResult
    private func failAStart(_ assembly: PersistentPlaybackAssembly,
                            songIDs: [String]) async -> Error? {
        assembly.backend.activateAudioSession = { throw CocoaError(.fileNoSuchFile) }
        assembly.session.replaceQueue(songIDs: songIDs)
        do {
            try await assembly.controller.play()
            return nil
        } catch {
            return error
        }
    }

    private func makeSong(id: String) -> Song {
        Song(id: id, parent: nil, title: "Track \(id)",
             album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
             track: nil, year: nil, genre: nil, coverArt: nil,
             size: nil, contentType: nil, suffix: nil,
             duration: 4, bitRate: nil, path: nil,
             discNumber: nil, created: nil, starred: nil, userRating: nil,
             bpm: nil, replayGain: nil, musicBrainzId: nil)
    }

    private func drive(_ controller: GaplessPlaybackController, seconds: Double,
                       until predicate: () -> Bool = { false }) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            await controller.tick()
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(4))
        }
    }

    // MARK: - 1. The failure itself

    /// A start whose audio-session activation is refused ends in `.failed`, with the graph not
    /// running and the node not playing.
    @Test func aStartFailureEntersFailed() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["t0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }

            let error = await failAStart(assembly, songIDs: ["t0"])

            #expect(error != nil, "the fixture start did not fail")
            #expect(assembly.backend.state == .failed,
                    "state was \(assembly.backend.state), expected failed")
            #expect(assembly.backend.engine.engine.isRunning == false)
            #expect(assembly.backend.engine.player.isPlaying == false)
        }
    }

    /// And while it stays `.failed`, a start is refused deterministically rather than half-run.
    @Test func aStartFromFailedIsRefusedRatherThanHalfRun() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["t0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            await failAStart(assembly, songIDs: ["t0"])
            // Even with the failure cause removed, `.failed` is not a startable state.
            assembly.backend.activateAudioSession = nil

            var thrown: Error?
            do { try assembly.backend.start() } catch { thrown = error }

            #expect(thrown != nil, "a start from .failed was allowed to proceed")
            #expect(assembly.backend.state == .failed)
            #expect(assembly.backend.engine.engine.isRunning == false)
        }
    }

    // MARK: - 2/3/4/5/6. What the reset actually releases

    /// The reset returns the backend to `.idle` **and** releases everything the failed attempt
    /// built: tail, buffers, pool, source files, converters, boundary and materialization records.
    @Test func resetFromFailedReturnsToIdleAndReleasesEverything() async throws {
        try await withTemporaryDirectory { directory in
            // 48 kHz against the 44.1 kHz graph, so a converter genuinely exists to be released.
            let files = try makeFiles(["t0"], in: directory, sampleRate: 48_000)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            let backend = assembly.backend

            await failAStart(assembly, songIDs: ["t0"])
            let scheduler = backend.bufferScheduler
            let staleTail = backend.tailGeneration

            // Preconditions: the failed attempt really is holding things. A fixture that scheduled
            // nothing would make every assertion below pass for the wrong reason.
            #expect(backend.scheduledSegments.isEmpty == false,
                    "the fixture failed before anything was scheduled")
            #expect(scheduler.liveSourceCount > 0, "no live source to release")
            #expect(scheduler.activeConverterCount > 0,
                    "no converter was built for a 48 kHz source, so the fixture proves nothing")
            #expect(scheduler.pool.inFlightCount > 0, "no pool buffers were out")
            #expect(backend.openFileCount > 0, "no source file was open")

            backend.resetAfterFailure()

            #expect(backend.state == .idle, "state was \(backend.state), expected idle")
            #expect(backend.engine.player.isPlaying == false)
            #expect(backend.engine.engine.isRunning == false)
            // Tail and timeline.
            #expect(backend.scheduledSegments.isEmpty,
                    "\(backend.scheduledSegments.count) segments survived the reset")
            #expect(scheduler.inFlightChunks.isEmpty,
                    "\(scheduler.inFlightChunks.count) chunks were never reconciled")
            #expect(backend.renderFrame == 0, "the timeline did not return to zero")
            // Pool.
            #expect(scheduler.pool.inFlightCount == 0, "buffers stayed out of the pool")
            #expect(scheduler.pool.availableCount == scheduler.pool.capacity,
                    "pool recovered \(scheduler.pool.availableCount) of \(scheduler.pool.capacity)")
            #expect(scheduler.chunkAccountingBalances,
                    "scheduled chunks did not reconcile against recycled + reclaimed")
            // Sources and converters.
            #expect(scheduler.liveSourceCount == 0,
                    "\(scheduler.liveSourceCount) sources stayed live")
            #expect(scheduler.activeConverterCount == 0,
                    "\(scheduler.activeConverterCount) converters stayed live")
            #expect(backend.openFileCount == 0, "\(backend.openFileCount) files stayed open")
            // Occurrence identity.
            #expect(scheduler.materializedInstances.isEmpty,
                    "materialized-instance records survived the failed session")
            #expect(backend.drainBoundaryEvents().isEmpty, "boundary events survived")
            #expect(backend.isCurrentTail(staleTail) == false,
                    "a callback from the failed session would still be treated as live")
        }
    }

    /// The reset does not merely relabel the state: everything above is released *before* `.idle`
    /// is published, so nothing can observe an idle backend that is still holding buffers.
    @Test func theStateIsNotIdleUntilTheResourcesAreActuallyReleased() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["t0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            let backend = assembly.backend
            await failAStart(assembly, songIDs: ["t0"])

            // Observed from the deactivation hook, which the release path runs as its last step.
            var stateAtRelease: GaplessEngineState?
            var inFlightAtRelease: Int?
            backend.deactivateAudioSession = {
                stateAtRelease = backend.state
                inFlightAtRelease = backend.bufferScheduler.pool.inFlightCount
            }

            backend.resetAfterFailure()

            #expect(stateAtRelease == .failed,
                    "the backend published .idle before its resources were released")
            #expect(inFlightAtRelease == 0, "the pool had not been reclaimed by release time")
            #expect(backend.state == .idle)
        }
    }

    // MARK: - 8/9/10. Reset from every other state

    /// Repeated resets are idempotent: the second sees `.idle` and does nothing.
    @Test func repeatedResetIsIdempotent() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["t0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            let backend = assembly.backend
            await failAStart(assembly, songIDs: ["t0"])

            backend.resetAfterFailure()
            let tailAfterFirst = backend.tailGeneration
            let availableAfterFirst = backend.bufferScheduler.pool.availableCount

            for _ in 0..<5 { backend.resetAfterFailure() }

            #expect(backend.state == .idle)
            #expect(backend.tailGeneration == tailAfterFirst,
                    "a no-op reset still churned the tail generation")
            #expect(backend.bufferScheduler.pool.availableCount == availableAfterFirst)
            #expect(backend.bufferScheduler.pool.inFlightCount == 0)
        }
    }

    /// A reset on a backend that never ran is harmless, and starts nothing.
    @Test func resetFromIdleIsHarmless() {
        let backend = GaplessRealTimeBackend()
        var deactivations = 0
        backend.deactivateAudioSession = { deactivations += 1 }

        backend.resetAfterFailure()
        backend.resetAfterFailure()

        #expect(backend.state == .idle)
        #expect(backend.engine.engine.isRunning == false)
        #expect(deactivations == 0,
                "a reset from idle touched the audio session it never owned")
    }

    /// A reset must never stand in for a stop: an actually-playing session keeps playing.
    @Test func resetDoesNotTearDownAnActivePlayingSession() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["t0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            let backend = assembly.backend
            assembly.session.replaceQueue(songIDs: ["t0"])

            try await assembly.controller.play()
            #expect(backend.state == .playing, "the fixture did not reach .playing")
            let segmentsBefore = backend.scheduledSegments.count
            let inFlightBefore = backend.bufferScheduler.pool.inFlightCount

            backend.resetAfterFailure()

            #expect(backend.state == .playing,
                    "a live session was reset as though it had already failed")
            #expect(backend.engine.engine.isRunning, "the reset stopped a running engine")
            #expect(backend.engine.player.isPlaying, "the reset stopped an audible node")
            #expect(backend.scheduledSegments.count == segmentsBefore,
                    "the reset discarded a playing session's tail")
            #expect(backend.bufferScheduler.pool.inFlightCount == inFlightBefore)
        }
    }

    /// A paused session is live too — pausing is not failing.
    @Test func resetDoesNotTearDownAPausedSession() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["t0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            let backend = assembly.backend
            assembly.session.replaceQueue(songIDs: ["t0"])

            try await assembly.controller.play()
            backend.pause()
            #expect(backend.state == .paused)
            let segmentsBefore = backend.scheduledSegments.count

            backend.resetAfterFailure()

            #expect(backend.state == .paused, "a paused session was reset as though it had failed")
            #expect(backend.scheduledSegments.count == segmentsBefore)
        }
    }

    /// Existing successful-stop behaviour is unchanged: a playing session still stops to `.idle`
    /// with everything released.
    @Test func aSuccessfulStopStillEndsTheSessionCleanly() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["t0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            let backend = assembly.backend
            assembly.session.replaceQueue(songIDs: ["t0"])

            try await assembly.controller.play()
            #expect(backend.state == .playing)

            backend.stop()

            #expect(backend.state == .idle)
            #expect(backend.engine.engine.isRunning == false)
            #expect(backend.scheduledSegments.isEmpty)
            #expect(backend.bufferScheduler.pool.inFlightCount == 0)
            #expect(backend.bufferScheduler.pool.availableCount
                    == backend.bufferScheduler.pool.capacity)
            #expect(backend.bufferScheduler.liveSourceCount == 0)
        }
    }

    // MARK: - 11. The point of the whole change

    /// A failed first start, then a successful second start, on the **same backend instance** —
    /// which is what the retained production assembly actually does.
    @Test func aFailedStartCanBeFollowedByASuccessfulStartOnTheSameBackend() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["t0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            let backend = assembly.backend

            await failAStart(assembly, songIDs: ["t0"])
            #expect(backend.state == .failed)
            backend.resetAfterFailure()
            #expect(backend.state == .idle)

            // Second session on the same instance, with the failure cause removed.
            backend.activateAudioSession = nil
            var audibleOccurrences = 0
            assembly.controller.onFirstAudibleSample = { audibleOccurrences += 1 }
            assembly.session.replaceQueue(songIDs: ["t0"])
            try await assembly.controller.play()

            #expect(backend.state == .playing,
                    "the second start left the backend in \(backend.state)")
            #expect(backend.engine.engine.isRunning, "the second start never ran the engine")

            // And it renders real audio, not merely a state transition. The clock is the check
            // that matters: the first occurrence's boundary is reported at frame 0 (its start
            // frame is 0, so it is audible the moment it is materialized), which proves the
            // segment exists but not that the engine is producing.
            await drive(assembly.controller, seconds: 5) {
                audibleOccurrences >= 1 && backend.renderFrame > 0
            }
            #expect(audibleOccurrences == 1,
                    "the recovered session became audible \(audibleOccurrences) times, expected 1")
            #expect(backend.renderFrame > 0, "the recovered engine rendered no audio")
        }
    }

    // MARK: - 13. Ownership left behind

    /// The reset leaves no audio-session claim and no signal ownership of any kind.
    @Test func resetLeavesNoAudioSessionOrSignalOwnership() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["t0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            let backend = assembly.backend
            let categoryBefore = AVAudioSession.sharedInstance().category
            let modeBefore = AVAudioSession.sharedInstance().mode
            let registrationsBefore = RemoteCommandManager.shared.registrationCount

            await failAStart(assembly, songIDs: ["t0"])
            var deactivations = 0
            backend.deactivateAudioSession = { deactivations += 1 }

            backend.resetAfterFailure()

            #expect(deactivations == 1,
                    "the failed session kept its audio-session claim (\(deactivations) releases)")
            #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                    "the reset changed the audio session category")
            #expect(AVAudioSession.sharedInstance().mode == modeBefore)
            // Nothing persistent ever registered a remote command, published Now Playing, claimed a
            // scrobble or took the visualizer feed — none of that is wired in this lane, and the
            // reset must not have introduced it.
            #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore)
            #expect(ApplicationPlayback.router?.ownership.authority == PlaybackAuthority.none,
                    "a backend reset moved application playback authority")
            #expect(ApplicationPlayback.router?.selectedBackend == .legacy)
        }
    }

    // MARK: - 7/12. Through the executor

    /// Pre-audible fallback leaves the retained assembly genuinely reusable: the backend is idle,
    /// its resources are released, the failed session's audible callback is gone, and a fresh
    /// persistent session starts and becomes audible on that same assembly.
    @Test func executorFallbackLeavesTheAssemblyReusable() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["t0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            let backend = assembly.backend
            backend.activateAudioSession = { throw CocoaError(.fileNoSuchFile) }

            let song = makeSong(id: "t0")
            let planner = PlaybackSessionSelectionPlanner(
                prepareAssembly: { assembly }, isPersistentRoutingEnabled: { true })
            let plan = await planner.plan(
                request: PlaybackSessionSelectionRequest(songs: [song], generation: 1))
            guard case .persistent = plan else {
                Issue.record("fixture should plan persistent: \(plan.describedForDiagnostics)")
                return
            }

            let legacy = LegacyPortSpy()
            let port = PersistentAssemblySessionPort(assembly: assembly)
            let executor = PlaybackSessionPlanExecutor(legacy: legacy, persistent: port)
            legacy.ownership = executor.ownership

            let outcome = await executor.execute(
                plan: plan,
                request: PlaybackSessionSelectionRequest(songs: [song], generation: 1),
                currentGeneration: 1)

            #expect(outcome == .fellBackToLegacy(.persistentStartFailed))
            #expect(executor.ownership.authority == .legacy)
            // The assembly is reusable, not merely quiet.
            #expect(backend.state == .idle,
                    "fallback left the retained backend in \(backend.state)")
            #expect(backend.scheduledSegments.isEmpty)
            #expect(backend.bufferScheduler.pool.inFlightCount == 0)
            #expect(backend.bufferScheduler.pool.availableCount
                    == backend.bufferScheduler.pool.capacity)
            #expect(backend.bufferScheduler.liveSourceCount == 0)
            #expect(backend.openFileCount == 0)
            #expect(assembly.controller.onFirstAudibleSample == nil,
                    "the failed session's audible callback outlived it")

            // And a later session really does play on the same instance.
            backend.activateAudioSession = nil
            var audibleOccurrences = 0
            assembly.controller.onFirstAudibleSample = { audibleOccurrences += 1 }
            assembly.session.replaceQueue(songIDs: ["t0"])
            try await assembly.controller.play()
            await drive(assembly.controller, seconds: 5) {
                audibleOccurrences >= 1 && backend.renderFrame > 0
            }

            #expect(backend.state == .playing)
            #expect(audibleOccurrences == 1,
                    "the reused assembly became audible \(audibleOccurrences) times, expected 1")
            #expect(backend.renderFrame > 0, "the reused assembly rendered no audio")
        }
    }
}
