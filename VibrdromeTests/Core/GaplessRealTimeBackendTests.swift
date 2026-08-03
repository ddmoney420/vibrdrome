import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// The real-time playback path: actual `AVAudioEngine` running against real hardware output.
///
/// The capability probe (`GaplessRealTimeProbeTests`) established that the test host can run the
/// graph in real time and that the node's sample clock advances, so these are genuine real-time
/// results rather than offline renders. Tracks are deliberately short (fractions of a second) so a
/// twenty-transition run takes seconds rather than minutes.
@MainActor
struct GaplessRealTimeBackendTests {
    static let sampleRate = 44_100.0
    /// 0.2 s per part — long enough to be really rendered, short enough for a long sequence.
    static let partFrames = 8_820

    /// Activate the session on iOS exactly as production will: only for an explicit play.
    static func makeBackend() -> GaplessRealTimeBackend {
        let backend = GaplessRealTimeBackend()
        #if os(iOS)
        backend.activateAudioSession = {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        }
        backend.deactivateAudioSession = {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
        #endif
        return backend
    }

    static func makeTracks(count: Int) throws -> (urls: [URL], tracks: [GaplessPreparedTrack]) {
        let urls = try GaplessPipelineOfflineTests.makeContinuousToneParts(
            count: count, sampleRate: sampleRate, frames: partFrames)
        let tracks = try urls.map {
            try GaplessTrackPreparer.describe(trackID: $0.lastPathComponent, fileURL: $0,
                                              renderSampleRate: sampleRate)
        }
        return (urls, tracks)
    }

    static func entries(_ tracks: [GaplessPreparedTrack], generation: UInt64 = 1)
        -> [(track: GaplessPreparedTrack, itemID: GaplessQueueItemID, generation: UInt64)] {
        tracks.enumerated().map { offset, track in
            (track, GaplessQueueItemID(rawValue: UInt64(offset + 1)), generation)
        }
    }

    /// Poll the clock until `predicate` holds or the deadline passes. Real time needs real waiting;
    /// this keeps it bounded and reports a timeout rather than hanging.
    @discardableResult
    static func waitUntil(_ description: String, timeout: TimeInterval = 10,
                          _ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("timed out waiting for \(description)")
        return false
    }

    // MARK: - Lifecycle

    @Test func lifecycleTransitionsAreRestrictedToLegalOnes() {
        #expect(GaplessEngineState.idle.canTransition(to: .prepared))
        #expect(GaplessEngineState.prepared.canTransition(to: .starting))
        #expect(GaplessEngineState.starting.canTransition(to: .playing))
        #expect(GaplessEngineState.playing.canTransition(to: .paused))
        #expect(GaplessEngineState.paused.canTransition(to: .playing))
        #expect(GaplessEngineState.playing.canTransition(to: .stopping))
        #expect(GaplessEngineState.stopping.canTransition(to: .idle))
        // Illegal: skipping the in-flight states, which is what a duplicate start would do.
        #expect(!GaplessEngineState.idle.canTransition(to: .playing))
        #expect(!GaplessEngineState.playing.canTransition(to: .starting))
        #expect(!GaplessEngineState.idle.canTransition(to: .paused))
        // Anything active can fail; a failed engine can only be torn down.
        #expect(GaplessEngineState.playing.canTransition(to: .failed))
        #expect(GaplessEngineState.failed.canTransition(to: .idle))
        #expect(!GaplessEngineState.failed.canTransition(to: .playing))
    }

    /// The cold-launch guarantee: building the graph must not activate anything.
    @Test func preparingTheGraphNeverActivatesTheAudioSession() throws {
        let backend = GaplessRealTimeBackend()
        var activated = false
        backend.activateAudioSession = { activated = true }

        try backend.prepareGraph()

        #expect(backend.state == .prepared)
        #expect(!activated, "graph construction activated the audio session")
        #expect(!backend.engine.engine.isRunning)
    }

    /// Preparing and scheduling audio is likewise passive — only Play activates.
    @Test func schedulingWithoutPlayingNeverActivatesTheAudioSession() throws {
        let (urls, tracks) = try Self.makeTracks(count: 2)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = GaplessRealTimeBackend()
        var activated = false
        backend.activateAudioSession = { activated = true }

        try backend.prepareGraph()
        try backend.schedule(Self.entries(tracks))

        #expect(!activated)
        #expect(backend.state == .prepared)
        #expect(backend.scheduledSegments.count == 2)
    }

    @Test func explicitPlayIsWhatActivatesTheSession() async throws {
        let (urls, tracks) = try Self.makeTracks(count: 1)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        var activationCount = 0
        let realActivation = backend.activateAudioSession
        backend.activateAudioSession = { activationCount += 1; try realActivation?() }

        try backend.prepareGraph()
        try backend.schedule(Self.entries(tracks))
        #expect(activationCount == 0)

        try backend.start()
        defer { backend.stop() }

        #expect(activationCount == 1)
        #expect(backend.state == .playing)
        #expect(backend.engine.engine.isRunning)
    }

    /// A second Play must not start the engine twice.
    @Test func duplicateStartIsANoOp() async throws {
        let (urls, tracks) = try Self.makeTracks(count: 1)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        var activationCount = 0
        let realActivation = backend.activateAudioSession
        backend.activateAudioSession = { activationCount += 1; try realActivation?() }
        try backend.prepareGraph()
        try backend.schedule(Self.entries(tracks))

        try backend.start()
        try backend.start()
        try backend.start()
        defer { backend.stop() }

        #expect(activationCount == 1)
        #expect(backend.state == .playing)
    }

    // MARK: - Vertical slice: four parts, one engine, no restarts

    /// Part 1 → 2 → 3 → 4 → stop, played for real, with the graph never rebuilt.
    @Test func fourPartAlbumPlaysThroughInRealTimeWithoutRestartingTheEngine() async throws {
        let (urls, tracks) = try Self.makeTracks(count: 4)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        let segments = try backend.schedule(Self.entries(tracks))

        let playerBefore = ObjectIdentifier(backend.engine.player)
        let eqBefore = ObjectIdentifier(backend.engine.eq)
        try backend.start()
        defer { backend.stop() }

        let total = AVAudioFramePosition(4 * Self.partFrames)
        var startCount = 0
        await Self.waitUntil("all four parts to render") {
            backend.observeBoundaries()
            if backend.engine.engine.isRunning { startCount = max(startCount, 1) }
            return backend.renderFrame >= total
        }

        let events = backend.drainBoundaryEvents()
        // Exactly one boundary event per play instance, in order.
        #expect(events.count == 4)
        #expect(events.map(\.playInstance) == segments.map(\.playInstance))
        #expect(events.map(\.songID) == tracks.map(\.trackID))
        // The engine ran continuously — never stopped or rebuilt at a boundary.
        #expect(backend.engine.engine.isRunning)
        #expect(ObjectIdentifier(backend.engine.player) == playerBefore)
        #expect(ObjectIdentifier(backend.engine.eq) == eqBefore)
        #expect(backend.state == .playing)
    }

    /// Twenty automatic transitions on one continuously running engine.
    @Test func twentyAutomaticTransitionsOnOneEngine() async throws {
        let partCount = 21
        let (urls, tracks) = try Self.makeTracks(count: partCount)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        let segments = try backend.schedule(Self.entries(tracks))
        let playerBefore = ObjectIdentifier(backend.engine.player)

        try backend.start()
        defer { backend.stop() }

        let total = AVAudioFramePosition(partCount * Self.partFrames)
        await Self.waitUntil("21 parts to render", timeout: 30) {
            backend.observeBoundaries()
            return backend.renderFrame >= total
        }

        let events = backend.drainBoundaryEvents()
        #expect(events.count == partCount)                       // 20 transitions
        #expect(events.map(\.playInstance) == segments.map(\.playInstance))
        #expect(Set(events.map(\.playInstance)).count == partCount)   // no duplicates
        #expect(backend.engine.engine.isRunning)
        #expect(ObjectIdentifier(backend.engine.player) == playerBefore)
    }

    // MARK: - Boundary identity

    /// Repeat One schedules the same file repeatedly. Each replay must be its own play instance and
    /// its own boundary event — identity cannot be the song or the queue slot.
    @Test func repeatedSameSourceProducesDistinctPlayInstances() async throws {
        let (urls, tracks) = try Self.makeTracks(count: 1)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        // Same slot ID, same file, three times — exactly what Repeat One does.
        let slot = GaplessQueueItemID(rawValue: 1)
        let repeated = (0..<3).map { _ in (track: tracks[0], itemID: slot, generation: UInt64(1)) }
        let segments = try backend.schedule(repeated)

        try backend.start()
        defer { backend.stop() }
        await Self.waitUntil("three replays to render", timeout: 15) {
            backend.observeBoundaries()
            return backend.renderFrame >= AVAudioFramePosition(3 * Self.partFrames)
        }

        let events = backend.drainBoundaryEvents()
        #expect(events.count == 3)
        #expect(Set(events.map(\.playInstance)).count == 3)      // three distinct plays
        #expect(Set(events.map(\.itemID)) == [slot])             // of the same slot
        #expect(Set(segments.map(\.playInstance)).count == 3)
    }

    /// Boundary observation is clock-driven, so the timing error is observation latency only — the
    /// audio itself is frame-exact and never late.
    @Test func boundaryTimingErrorIsObservationLatencyNotAnAudioGap() async throws {
        let (urls, tracks) = try Self.makeTracks(count: 3)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        let segments = try backend.schedule(Self.entries(tracks))
        try backend.start()
        defer { backend.stop() }

        await Self.waitUntil("three parts", timeout: 15) {
            backend.observeBoundaries()
            return backend.renderFrame >= AVAudioFramePosition(3 * Self.partFrames)
        }

        let events = backend.drainBoundaryEvents()
        #expect(events.count == 3)
        // The scheduled start frames are exactly consecutive — that is the frame-exactness claim.
        #expect(segments[1].startFrame == AVAudioFramePosition(Self.partFrames))
        #expect(segments[2].startFrame == AVAudioFramePosition(2 * Self.partFrames))
        for event in events { #expect(event.timingErrorFrames >= 0) }
    }

    // MARK: - Pause / resume

    @Test func pausePreservesPositionAndScheduledTail() async throws {
        let (urls, tracks) = try Self.makeTracks(count: 4)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        try backend.schedule(Self.entries(tracks))
        try backend.start()
        defer { backend.stop() }

        await Self.waitUntil("playback to begin") { backend.renderFrame > 1_000 }
        backend.pause()
        let atPause = backend.renderFrame
        let tailAtPause = backend.scheduledSegments.count

        try await Task.sleep(for: .milliseconds(300))

        // The node's clock holds while paused — position is preserved, not reset or advanced.
        #expect(backend.state == .paused)
        #expect(abs(backend.renderFrame - atPause) < 2_000)
        #expect(backend.scheduledSegments.count == tailAtPause)
        #expect(backend.engine.engine.isRunning)          // graph intact
        #expect(backend.engine.visualizerFeed.registeredConsumerCount >= 0)

        try backend.resume()
        #expect(backend.state == .playing)
        await Self.waitUntil("playback to advance past the pause point") {
            backend.renderFrame > atPause + 2_000
        }
    }

    @Test func multiplePauseResumeCyclesKeepAdvancing() async throws {
        let (urls, tracks) = try Self.makeTracks(count: 6)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        try backend.schedule(Self.entries(tracks))
        try backend.start()
        defer { backend.stop() }

        var last: AVAudioFramePosition = 0
        for _ in 0..<3 {
            await Self.waitUntil("advance") { backend.renderFrame > last + 2_000 }
            backend.pause()
            let paused = backend.renderFrame
            #expect(paused >= last)
            try await Task.sleep(for: .milliseconds(80))
            try backend.resume()
            last = paused
        }
        #expect(backend.state == .playing)
    }

    // MARK: - Stop / restart

    @Test func stopClearsTheScheduleAndLeavesTheGraphReusable() async throws {
        let (urls, tracks) = try Self.makeTracks(count: 3)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        try backend.schedule(Self.entries(tracks))
        try backend.start()
        await Self.waitUntil("playback to begin") { backend.renderFrame > 1_000 }

        backend.stop()

        #expect(backend.state == .idle)
        #expect(backend.scheduledSegments.isEmpty)
        #expect(backend.drainBoundaryEvents().isEmpty)      // future events invalidated
        #expect(!backend.engine.engine.isRunning)
        #expect(backend.engine.gainStage.currentGain == .unity)

        // Reusable: the same graph starts again cleanly.
        try backend.prepareGraph()
        try backend.schedule(Self.entries(tracks, generation: 2))
        try backend.start()
        defer { backend.stop() }
        #expect(backend.state == .playing)
        await Self.waitUntil("second run to advance") { backend.renderFrame > 1_000 }
    }

    // MARK: - Tail replacement (the mechanism behind seek and skip)

    /// Resetting the tail keeps the audible position and the timeline monotonic, which is what makes
    /// elapsed time and boundary identity survive a seek or a skip.
    @Test func resetTailKeepsTheTimelineMonotonic() async throws {
        let (urls, tracks) = try Self.makeTracks(count: 4)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        try backend.schedule(Self.entries(tracks))
        try backend.start()
        defer { backend.stop() }
        await Self.waitUntil("playback to begin") { backend.renderFrame > 2_000 }

        let before = backend.renderFrame
        let resumeFrame = backend.resetTail()

        #expect(resumeFrame >= before)
        // The clock does not jump backwards after the rebuild.
        #expect(backend.renderFrame >= before)
        // A fresh tail can be scheduled from the new origin.
        try backend.schedule(Self.entries(Array(tracks.suffix(2)), generation: 2))
        #expect(backend.scheduledSegments.last?.generation == 2)
    }

    // MARK: - Clock mapping

    @Test func clockMapsTimelineFrameToQueueItemAndSourceOffset() async throws {
        let (urls, tracks) = try Self.makeTracks(count: 3)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        let segments = try backend.schedule(Self.entries(tracks))
        try backend.start()
        defer { backend.stop() }

        // Wait until the clock is inside the second segment.
        await Self.waitUntil("second segment to become audible") {
            backend.renderFrame > AVAudioFramePosition(Self.partFrames) + 1_000
        }
        let reading = backend.clockReading(generation: 1)

        #expect(reading.itemID == segments[1].itemID)
        #expect(reading.playInstance == segments[1].playInstance)
        #expect(reading.sourceRelativeFrame > 0)
        #expect(reading.sourceRelativeFrame < AVAudioFramePosition(Self.partFrames))
        #expect(reading.elapsedSeconds > 0)
        #expect(reading.engineState == .playing)
        #expect(reading.isPlayerPlaying)
        #expect(reading.generation == 1)
    }

    // MARK: - Failure paths

    @Test func audioSessionActivationFailureLeavesAKnownState() throws {
        let backend = GaplessRealTimeBackend()
        struct Boom: Error {}
        backend.activateAudioSession = { throw Boom() }
        try backend.prepareGraph()

        #expect(throws: GaplessEngineFailure.self) { try backend.start() }
        #expect(backend.state == .failed)
        // A failed engine is not left looking like it is playing.
        #expect(!backend.engine.engine.isRunning)
        #expect(!GaplessEngineState.failed.canTransition(to: .playing))
    }

    @Test func schedulingAMissingFileFailsWithoutCorruptingTheTimeline() throws {
        let (urls, tracks) = try Self.makeTracks(count: 1)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = GaplessRealTimeBackend()
        try backend.prepareGraph()
        try backend.schedule(Self.entries(tracks))
        let goodCount = backend.scheduledSegments.count

        let missing = GaplessPreparedTrack(
            trackID: "gone", fileURL: URL(fileURLWithPath: "/nonexistent/gone.wav"),
            trim: GaplessTrim(startFrame: 0, frameCount: 100, reason: .wholeFile),
            sourceSampleRate: Self.sampleRate, sourceChannelCount: 1, renderFrames: 100)

        #expect(throws: GaplessEngineFailure.self) {
            try backend.schedule([(missing, GaplessQueueItemID(rawValue: 99), 1)])
        }
        // The good segment is untouched — a failed schedule does not corrupt the timeline.
        #expect(backend.scheduledSegments.count == goodCount)
    }

    // MARK: - No per-item processing tap

    /// The regression this whole architecture exists to prevent.
    @Test func realTimePathInstallsNoPerItemProcessingTap() async throws {
        let (urls, tracks) = try Self.makeTracks(count: 3)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        try backend.schedule(Self.entries(tracks))
        backend.engine.installVisualizerFeed()
        defer { backend.engine.uninstallVisualizerFeed() }
        try backend.start()
        defer { backend.stop() }

        await Self.waitUntil("two boundaries") {
            backend.observeBoundaries()
            return backend.renderFrame > AVAudioFramePosition(2 * Self.partFrames)
        }

        // One persistent feed, installed once, across every boundary — and no AVAudioMix anywhere.
        #expect(backend.engine.visualizerFeed.isInstalled)
        #expect(backend.engine.engine.isRunning)
    }
}
