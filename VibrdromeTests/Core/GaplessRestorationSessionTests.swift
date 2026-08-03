import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Restoration, audio-session lifecycle, interruption, and passive reconstruction.
///
/// The single property running through all of it: **nothing but an explicit playback action may
/// activate the audio session**. That is the Build 60 cold-launch fix (#134), and it is the one
/// behaviour here with a side effect the user can hear in another app.
@MainActor
struct GaplessRestorationSessionTests {
    static let sampleRate = 44_100.0
    static let trackFrames = 8_820
    static let tones: [Double] = [233, 379, 611, 977]

    static func makeSession(_ songIDs: [String], duration: TimeInterval = 100)
        -> GaplessPlaybackSession {
        let session = GaplessPlaybackSession(sampleRate: sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = duration }
        return session
    }

    static func state(_ songIDs: [String], index: Int = 0, elapsed: TimeInterval = 0,
                      repeatMode: RepeatMode = .off,
                      shuffle: Bool = false) -> GaplessRestorationState {
        GaplessRestorationState(songIDs: songIDs, currentIndex: index, elapsedSeconds: elapsed,
                                repeatMode: repeatMode, shuffleEnabled: shuffle)
    }

    // MARK: - Restoration mapping

    /// Persisted repeat values map exactly as production writes them; anything unknown falls back to
    /// `off` rather than failing the whole restoration for one bad field.
    @Test(arguments: [("off", RepeatMode.off), ("all", .all), ("one", .one),
                      ("garbage", .off), ("", .off)])
    func persistedRepeatValueMapsSafely(scenario: (raw: String, expected: RepeatMode)) {
        #expect(GaplessRestorationState.repeatMode(fromPersisted: scenario.raw) == scenario.expected)
    }

    @Test func restorationLoadsQueueRepeatAndShuffle() {
        let session = Self.makeSession([])
        let coordinator = GaplessRestorationCoordinator(session: session)

        let outcome = coordinator.restorePassively(
            Self.state(["a", "b", "c"], index: 1, elapsed: 30, repeatMode: .all, shuffle: true),
            durations: ["a": 100, "b": 100, "c": 100])

        #expect(outcome == .restored(elapsedSeconds: 30, currentIndex: 1))
        #expect(session.queue.items.map(\.songID) == ["a", "b", "c"])
        #expect(session.queue.currentIndex == 1)
        #expect(session.queue.repeatMode == .all)
        #expect(session.queue.shuffleEnabled)
        // Restoration always comes back paused — no playing state is persisted.
        #expect(!session.isPlaying)
    }

    // MARK: - Passive restoration must never activate

    /// The headline guarantee: a full restoration performs zero session activations.
    @Test func restorationPerformsZeroSessionActivations() throws {
        let session = Self.makeSession([])
        let coordinator = GaplessRestorationCoordinator(session: session)
        let audio = GaplessAudioSessionCoordinator()
        var configured = 0
        var activated = 0
        audio.configureSession = { configured += 1 }
        audio.activateSession = { activated += 1 }

        // Everything an app does on cold launch, in order.
        audio.configureAtLaunch()
        let backend = GaplessRealTimeBackend()
        backend.activateAudioSession = { try audio.activateForPlayback() }
        try backend.prepareGraph()                       // build the graph
        backend.engine.installVisualizerFeed()           // install the persistent tap
        defer { backend.engine.uninstallVisualizerFeed() }
        coordinator.restorePassively(Self.state(["a", "b"], elapsed: 12),
                                     durations: ["a": 100, "b": 100])
        let bridge = GaplessNowPlayingBridge()
        bridge.trackBecameAudible(GaplessNowPlayingUpdate(
            songID: "a", itemID: session.queue.items[0].id,
            playInstance: GaplessPlayInstanceID(rawValue: 1), queueGeneration: session.queue.generation,
            tailGeneration: 1, scheduledStartFrame: 0, observedRenderFrame: 0,
            queueIndex: 0, elapsedSeconds: 12, isPlaying: false))

        // Configuration happened; activation did not.
        #expect(configured == 1)
        #expect(activated == 0, "restoration activated the audio session")
        #expect(audio.activationCount == 0)
        #expect(!audio.isActive)
        #expect(backend.state == .prepared)
        #expect(!backend.engine.engine.isRunning)
    }

    /// Restored Now Playing shows the current item, paused, at the restored position — and never a
    /// future queue item.
    @Test func restoredNowPlayingShowsTheCurrentItemPausedAtPosition() {
        let session = Self.makeSession([])
        let coordinator = GaplessRestorationCoordinator(session: session)
        coordinator.restorePassively(Self.state(["first", "second"], index: 0, elapsed: 42),
                                     durations: ["first": 100, "second": 100])
        let bridge = GaplessNowPlayingBridge()
        var published: [GaplessNowPlayingUpdate] = []
        var elapsedWrites: [(TimeInterval, Bool)] = []
        bridge.publishMetadata = { published.append($0) }
        bridge.publishElapsed = { elapsedWrites.append(($0, $1)) }

        bridge.trackBecameAudible(GaplessNowPlayingUpdate(
            songID: "first", itemID: session.queue.items[0].id,
            playInstance: GaplessPlayInstanceID(rawValue: 1), queueGeneration: session.queue.generation,
            tailGeneration: 1, scheduledStartFrame: 0, observedRenderFrame: 0,
            queueIndex: 0, elapsedSeconds: 42, isPlaying: false))
        bridge.publishElapsedImmediately(seconds: 42, isPlaying: false)

        #expect(published.count == 1)
        #expect(published[0].songID == "first")           // never the future item
        #expect(published[0].queueIndex == 0)
        #expect(!published[0].isPlaying)                  // rate 0
        #expect(elapsedWrites.count == 1)
        #expect(elapsedWrites[0].0 == 42)
        #expect(elapsedWrites[0].1 == false)
    }

    // MARK: - Explicit Play activates exactly once

    @Test func explicitPlayActivatesExactlyOnceAndRepeatedPlayDoesNot() throws {
        let audio = GaplessAudioSessionCoordinator()
        var activated = 0
        audio.activateSession = { activated += 1 }

        #expect(try audio.activateForPlayback())
        // Already active: a repeated Play must not churn the session.
        #expect(try !audio.activateForPlayback())
        #expect(try !audio.activateForPlayback())

        #expect(activated == 1)
        #expect(audio.activationCount == 1)
        #expect(audio.isActive)
    }

    @Test func activationFailureIsReportedAndLeavesTheSessionInactive() {
        let audio = GaplessAudioSessionCoordinator()
        struct Boom: Error {}
        audio.activateSession = { throw Boom() }

        #expect(throws: GaplessEngineFailure.self) { try audio.activateForPlayback() }
        #expect(!audio.isActive)
        #expect(audio.activationCount == 0)
    }

    /// Production never deactivates — not on pause, not on stop, and never with
    /// `notifyOthersOnDeactivation`. Preserved rather than "improved".
    @Test func pauseAndStopDoNotDeactivateTheSession() throws {
        let audio = GaplessAudioSessionCoordinator()
        var activated = 0
        audio.activateSession = { activated += 1 }
        try audio.activateForPlayback()

        audio.pause()
        #expect(audio.isActive)
        audio.stop()
        #expect(audio.isActive)

        // Resuming after a pause does not re-activate, because it was never deactivated.
        #expect(try !audio.activateForPlayback())
        #expect(activated == 1)
    }

    // MARK: - Restored position validation

    @Test(arguments: [
        (persisted: 0.0, duration: 100.0, expected: 0.0),
        (persisted: 45.0, duration: 100.0, expected: 45.0),
        (persisted: 99.9, duration: 100.0, expected: 99.9),
        (persisted: 100.0, duration: 100.0, expected: 0.0),      // at the end → restart
        (persisted: 500.0, duration: 100.0, expected: 0.0),      // past the end → restart
        (persisted: -5.0, duration: 100.0, expected: 0.0),       // negative → start
        (persisted: 30.0, duration: 0.0, expected: 30.0)         // unknown duration → trust it
    ])
    func restoredPositionIsClamped(scenario: (persisted: TimeInterval, duration: TimeInterval,
                                              expected: TimeInterval)) {
        let duration: TimeInterval? = scenario.duration > 0 ? scenario.duration : nil
        #expect(GaplessRestorationCoordinator.clampedElapsed(scenario.persisted,
                                                             duration: duration) == scenario.expected)
    }

    @Test func nonFinitePersistedPositionIsRejected() {
        #expect(GaplessRestorationCoordinator.clampedElapsed(.nan, duration: 100) == 0)
        #expect(GaplessRestorationCoordinator.clampedElapsed(.infinity, duration: 100) == 0)
    }

    // MARK: - Invalid restoration

    @Test func emptyPersistedQueueIsUnusableNotFatal() {
        let session = Self.makeSession([])
        let coordinator = GaplessRestorationCoordinator(session: session)

        let outcome = coordinator.restorePassively(Self.state([]))

        #expect(outcome == .unusable(reason: "empty queue"))
        #expect(session.queue.isEmpty)
    }

    @Test(arguments: [5, -1, 99])
    func outOfBoundsCurrentIndexIsCorrectedNotFatal(index: Int) {
        let session = Self.makeSession([])
        let coordinator = GaplessRestorationCoordinator(session: session)

        let outcome = coordinator.restorePassively(Self.state(["a", "b"], index: index, elapsed: 10),
                                                   durations: ["a": 100, "b": 100])

        // The queue is still usable; playback starts at the first item, and the reason is reported.
        if case .restoredWithCorrectedIndex(_, let corrected, let reason) = outcome {
            #expect(corrected == 0)
            #expect(!reason.isEmpty)
        } else {
            Issue.record("expected a corrected index, got \(outcome)")
        }
        #expect(session.queue.currentIndex == 0)
        #expect(session.queue.count == 2)
    }

    /// A restoration superseded by a newer user action must not apply when it finally completes.
    @Test func supersededRestorationIsRejected() {
        let session = Self.makeSession([])
        let coordinator = GaplessRestorationCoordinator(session: session)
        coordinator.restorePassively(Self.state(["old"]), durations: ["old": 100])
        let staleGeneration = coordinator.restorationGeneration

        // The user starts something else, which restores a different queue.
        coordinator.restorePassively(Self.state(["new"]), durations: ["new": 100])

        #expect(!coordinator.isCurrent(restorationGeneration: staleGeneration))
        #expect(coordinator.isCurrent(restorationGeneration: coordinator.restorationGeneration))
        coordinator.discardStaleRestoration()
        #expect(coordinator.discardedStaleRestorations == 1)
    }

    /// A restored track begins a NEW play instance, so it cannot inherit credit for audio the user
    /// may never have heard.
    @Test func restoredTrackStartsANewPlayInstanceAndMustEarnItsOwnScrobble() {
        #expect(GaplessRestorationCoordinator.restoredTrackStartsNewPlayInstance)
        let reporter = GaplessScrobbleReporter(sampleRate: Self.sampleRate)
        var submitted = 0
        reporter.submit = { _ in submitted += 1 }

        // The pre-restart play submitted already.
        _ = reporter.playEnded(songID: "s", itemID: GaplessQueueItemID(rawValue: 1),
                               playInstance: GaplessPlayInstanceID(rawValue: 1),
                               audibleFrames: AVAudioFramePosition(60 * Self.sampleRate),
                               durationSeconds: 100)
        #expect(submitted == 1)

        // After restoration the same slot resumes as a new instance with zero audible frames — it
        // must not submit again on the strength of the previous play.
        _ = reporter.playEnded(songID: "s", itemID: GaplessQueueItemID(rawValue: 1),
                               playInstance: GaplessPlayInstanceID(rawValue: 2),
                               audibleFrames: 0, durationSeconds: 100)
        #expect(submitted == 1)

        // Once genuinely re-heard past the threshold, it is eligible on its own merit.
        _ = reporter.playEnded(songID: "s", itemID: GaplessQueueItemID(rawValue: 1),
                               playInstance: GaplessPlayInstanceID(rawValue: 3),
                               audibleFrames: AVAudioFramePosition(60 * Self.sampleRate),
                               durationSeconds: 100)
        #expect(submitted == 2)
    }

    // MARK: - Interruption

    @Test func interruptionBeganCapturesStateWithoutCompletingThePlay() {
        let audio = GaplessAudioSessionCoordinator()
        let session = Self.makeSession(["a", "b"], duration: 10)
        session.play()
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        session.advance(renderedFrames: AVAudioFramePosition(2 * Self.sampleRate), boundaries: [])

        audio.interruptionBegan(wasPlaying: true)
        session.pause()

        #expect(audio.wasPlayingBeforeInterruption)
        #expect(audio.isInterrupted)
        #expect(!audio.isActive)                     // the system took the session
        // The play is not completed and no scrobble was produced by the interruption itself.
        #expect(session.audibleItemID == ids[0])
        #expect(session.queue.item(id: ids[0])?.state == .audible)
        #expect(!session.events.contains { if case .completed = $0 { return true }; return false })
    }

    /// The complete production truth table, including the case worth flagging.
    @Test(arguments: [
        (wasPlaying: false, systemShouldResume: false, expectResume: false),
        (wasPlaying: false, systemShouldResume: true, expectResume: true),
        (wasPlaying: true, systemShouldResume: false, expectResume: true),   // the OR-rule case
        (wasPlaying: true, systemShouldResume: true, expectResume: true)
    ])
    func interruptionEndedTruthTable(scenario: (wasPlaying: Bool, systemShouldResume: Bool,
                                                expectResume: Bool)) throws {
        let audio = GaplessAudioSessionCoordinator()
        var activated = 0
        audio.activateSession = { activated += 1 }
        audio.interruptionBegan(wasPlaying: scenario.wasPlaying)

        let resume = try audio.interruptionEnded(systemShouldResume: scenario.systemShouldResume)

        #expect(resume == scenario.expectResume,
                "wasPlaying=\(scenario.wasPlaying) shouldResume=\(scenario.systemShouldResume)")
        // Production reactivates on `.ended` regardless of whether it then resumes.
        #expect(activated == 1)
        #expect(audio.isActive)
        #expect(!audio.isInterrupted)
        // The captured flag is consumed, so a later interruption starts clean.
        #expect(!audio.wasPlayingBeforeInterruption)
    }

    /// Pinned explicitly: the OR rule resumes even when the system says not to.
    @Test func theOrRuleResumesAgainstAnExplicitSystemNo() {
        let audio = GaplessAudioSessionCoordinator()
        audio.interruptionBegan(wasPlaying: true)

        #expect(audio.shouldResumeAfterInterruption(systemShouldResume: false))
        #expect(!GaplessAudioSessionCoordinator.resumePolicyNote.isEmpty)
    }

    /// Resuming from an interruption keeps the same play instance and does not reset eligibility —
    /// an interruption is a pause, not a new play.
    @Test func resumeAfterInterruptionPreservesPlayInstanceAndEligibility() async throws {
        let session = Self.makeSession(["a", "b"], duration: 10)
        session.play()
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        session.advance(renderedFrames: AVAudioFramePosition(6 * Self.sampleRate), boundaries: [])
        let framesBefore = session.queue.item(id: ids[0])?.audibleFrames ?? 0

        session.pause()                              // interruption began
        session.play()                               // interruption ended, resumed

        // Same audible item, same accumulated evidence — no duplicate audible-start.
        #expect(session.audibleItemID == ids[0])
        #expect(session.queue.item(id: ids[0])?.audibleFrames == framesBefore)
        let audibleStarts = session.events.filter {
            if case .becameAudible = $0 { return true }
            return false
        }
        #expect(audibleStarts.count == 1, "resume emitted a duplicate audible-start")
    }

    // MARK: - Passive reconstruction

    /// A configuration change or media-services reset rebuilds the graph without activating.
    @Test func reconstructionIsPassiveAndProducesExactlyOneOfEachComponent() throws {
        let audio = GaplessAudioSessionCoordinator()
        var activated = 0
        audio.activateSession = { activated += 1 }
        let backend = GaplessRealTimeBackend()
        backend.activateAudioSession = { try audio.activateForPlayback() }
        try backend.prepareGraph()
        try backend.start()
        #expect(activated == 1)

        // Capture the tail identity BEFORE teardown — stop() bumps it, which is precisely how
        // pre-reset callbacks become recognisable as stale.
        let staleTail = backend.tailGeneration
        // The engine goes away, as a configuration change or media-services reset forces.
        backend.stop()

        // Rebuild — passively.
        try backend.prepareGraph()
        backend.engine.installVisualizerFeed()
        backend.engine.installVisualizerFeed()       // repeat calls must not double-install
        defer { backend.engine.uninstallVisualizerFeed() }

        #expect(activated == 1, "reconstruction activated the audio session")
        #expect(backend.state == .prepared)
        #expect(!backend.engine.engine.isRunning)
        // Exactly one of each component; the graph is fixed, not accumulated.
        #expect(backend.engine.visualizerFeed.isInstalled)
        #expect(backend.engine.eq.bands.count == EQPresets.frequencies.count)
        // Callbacks from before the rebuild can no longer apply.
        #expect(!backend.isCurrentTail(staleTail))
        #expect(backend.scheduledSegments.isEmpty)
    }

    /// Repeated reset notifications must not accumulate components or observers.
    @Test func repeatedResetsDoNotAccumulateComponents() throws {
        let audio = GaplessAudioSessionCoordinator()
        var activated = 0
        audio.activateSession = { activated += 1 }
        let backend = GaplessRealTimeBackend()
        backend.activateAudioSession = { try audio.activateForPlayback() }
        let feed = backend.engine.visualizerFeed
        let classic = GaplessClassicVisualizerAdapter(feed: feed, sampleRate: Self.sampleRate)
        _ = classic

        for _ in 0..<5 {
            try backend.prepareGraph()
            backend.engine.installVisualizerFeed()
            backend.stop()
            backend.engine.uninstallVisualizerFeed()
        }

        #expect(activated == 0, "reconstruction must never activate")
        // One consumer registration despite five rebuild cycles.
        #expect(feed.registeredConsumerCount == 1)
        #expect(backend.state == .idle)
        #expect(backend.scheduledSegments.isEmpty)
    }

    /// Queue, position and metadata survive a reset; only the engine is rebuilt.
    @Test func resetPreservesQueuePositionAndMetadata() throws {
        let session = Self.makeSession(["a", "b", "c"], duration: 10)
        let coordinator = GaplessRestorationCoordinator(session: session)
        coordinator.restorePassively(Self.state(["a", "b", "c"], index: 1, elapsed: 4),
                                     durations: ["a": 10, "b": 10, "c": 10])
        let bridge = GaplessNowPlayingBridge()
        var published: [String] = []
        bridge.publishMetadata = { published.append($0.songID) }
        bridge.trackBecameAudible(GaplessNowPlayingUpdate(
            songID: "b", itemID: session.queue.items[1].id,
            playInstance: GaplessPlayInstanceID(rawValue: 1), queueGeneration: session.queue.generation,
            tailGeneration: 1, scheduledStartFrame: 0, observedRenderFrame: 0,
            queueIndex: 1, elapsedSeconds: 4, isPlaying: false))

        // Simulate the reset: the engine is discarded, the logical state is not.
        let backend = GaplessRealTimeBackend()
        backend.stop()
        try backend.prepareGraph()

        #expect(session.queue.count == 3)
        #expect(session.queue.currentIndex == 1)
        #expect(published == ["b"])
        #expect(bridge.lastUpdate?.songID == "b")
        #expect(backend.state == .prepared)
    }
}
