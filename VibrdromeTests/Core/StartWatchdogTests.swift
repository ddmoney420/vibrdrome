import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// The legacy track-start watchdog: closes the proven "isPlaying=true but the player never got an
/// audible item" blind spot. The decision policy and the mandatory generation/song fence are pure,
/// so both the state matrix and the race property are deterministically covered here. End-to-end
/// timing/recovery and explicit-Play-after-give-up are exercised on-device (they need a live stream).
@Suite(.serialized)
@MainActor
struct StartWatchdogTests {

    private func state(hasItem: Bool = true,
                       itemStatus: AVPlayerItem.Status? = .unknown,
                       noItemToPlay: Bool = false,
                       isPlayingNow: Bool = false,
                       elapsed: TimeInterval = 0,
                       attempts: Int = 0) -> StartWatchdogState {
        StartWatchdogState(hasItem: hasItem, itemStatus: itemStatus, noItemToPlay: noItemToPlay,
                           isPlayingNow: isPlayingNow, elapsed: elapsed, attempts: attempts)
    }

    // MARK: - Decision matrix

    /// A player that is actually playing means the start succeeded — disarm.
    @Test func playingDisarms() {
        #expect(AudioEngine.startWatchdogDecision(state(isPlayingNow: true)) == .disarm)
    }

    /// A ready item closes the start blind spot even before playback is observed — disarm.
    @Test func readyDisarms() {
        #expect(AudioEngine.startWatchdogDecision(state(itemStatus: .readyToPlay)) == .disarm)
    }

    /// A failed item is owned by the existing item-status retry, not the watchdog.
    @Test func failedDefersToExistingRecovery() {
        #expect(AudioEngine.startWatchdogDecision(state(itemStatus: .failed)) == .deferToFailure)
    }

    /// No item before the fast grace → keep waiting for the remaining time.
    @Test func noItemBeforeGraceWaits() {
        let decision = AudioEngine.startWatchdogDecision(
            state(hasItem: false, itemStatus: nil, elapsed: 1.0))
        guard case .wait(let delay) = decision else { Issue.record("expected .wait, got \(decision)"); return }
        #expect(abs(delay - (AudioEngine.startWatchdogNoItemGrace - 1.0)) < 0.01)
    }

    /// No item at/after the fast grace, attempts remaining → rebuild.
    @Test func noItemAtGraceRecovers() {
        let decision = AudioEngine.startWatchdogDecision(
            state(hasItem: false, itemStatus: nil,
                  elapsed: AudioEngine.startWatchdogNoItemGrace, attempts: 0))
        #expect(decision == .recover)
    }

    /// `noItemToPlay` is the empty-player pathology → treated on the fast grace like a missing item.
    @Test func noItemToPlayRecovers() {
        let decision = AudioEngine.startWatchdogDecision(
            state(hasItem: false, itemStatus: nil, noItemToPlay: true,
                  elapsed: AudioEngine.startWatchdogNoItemGrace + 0.5))
        #expect(decision == .recover)
    }

    /// A present-but-`.unknown` item before the patient grace → keep waiting (slow load is legit).
    @Test func unknownBeforeGraceWaits() {
        let decision = AudioEngine.startWatchdogDecision(
            state(hasItem: true, itemStatus: .unknown, elapsed: 5.0))
        guard case .wait(let delay) = decision else { Issue.record("expected .wait, got \(decision)"); return }
        #expect(abs(delay - (AudioEngine.startWatchdogUnknownGrace - 5.0)) < 0.01)
    }

    /// A present-but-`.unknown` item beyond the patient grace → rebuild.
    @Test func unknownBeyondGraceRecovers() {
        let decision = AudioEngine.startWatchdogDecision(
            state(hasItem: true, itemStatus: .unknown,
                  elapsed: AudioEngine.startWatchdogUnknownGrace, attempts: 0))
        #expect(decision == .recover)
    }

    /// After the max rebuilds, a still-missing item fails honestly.
    @Test func attemptsExhaustedGivesUp() {
        let decision = AudioEngine.startWatchdogDecision(
            state(hasItem: false, itemStatus: nil,
                  elapsed: AudioEngine.startWatchdogNoItemGrace + 1,
                  attempts: AudioEngine.startWatchdogMaxAttempts))
        #expect(decision == .giveUp)
    }

    /// A stuck `.unknown` also gives up once the rebuild budget is spent.
    @Test func unknownExhaustedGivesUp() {
        let decision = AudioEngine.startWatchdogDecision(
            state(hasItem: true, itemStatus: .unknown,
                  elapsed: AudioEngine.startWatchdogUnknownGrace + 1,
                  attempts: AudioEngine.startWatchdogMaxAttempts))
        #expect(decision == .giveUp)
    }

    // MARK: - Generation / song fencing (mandatory race property)

    /// A watchdog armed for song A must never act after song B has replaced it.
    @Test func fenceRejectsDifferentSong() {
        #expect(AudioEngine.startWatchdogPassesFence(
            capturedGeneration: 5, currentGeneration: 5,
            capturedSongId: "A", currentSongId: "B", isPlaying: true) == false)
    }

    /// A generation bump (a superseding swap/rebuild) invalidates the captured watchdog.
    @Test func fenceRejectsGenerationMismatch() {
        #expect(AudioEngine.startWatchdogPassesFence(
            capturedGeneration: 5, currentGeneration: 6,
            capturedSongId: "A", currentSongId: "A", isPlaying: true) == false)
    }

    /// If we no longer intend to play, the watchdog must not act.
    @Test func fenceRejectsNotPlaying() {
        #expect(AudioEngine.startWatchdogPassesFence(
            capturedGeneration: 5, currentGeneration: 5,
            capturedSongId: "A", currentSongId: "A", isPlaying: false) == false)
    }

    /// A disarmed watchdog (nil captured generation) never passes.
    @Test func fenceRejectsNilCaptured() {
        #expect(AudioEngine.startWatchdogPassesFence(
            capturedGeneration: nil, currentGeneration: 5,
            capturedSongId: nil, currentSongId: "A", isPlaying: true) == false)
    }

    /// Same generation + same song + still playing → the watchdog may act.
    @Test func fencePassesWhenAllMatch() {
        #expect(AudioEngine.startWatchdogPassesFence(
            capturedGeneration: 5, currentGeneration: 5,
            capturedSongId: "A", currentSongId: "A", isPlaying: true) == true)
    }

    // MARK: - Disarm mechanism (used by Stop / new swap / success / give-up)

    /// A media-services reset makes the legacy path report an honest not-playing/recoverable state
    /// and clears the pending-work budgets — never a phantom playing. It does NOT auto-resume.
    @Test func mediaServicesResetReportsHonestNotPlaying() {
        let engine = AudioEngine.shared
        engine.isPlaying = true
        engine.playbackStartFailed = false
        engine.failedRetryCount = 2
        engine.failedRetrySongId = "x"

        engine.handleMediaServicesReset()

        #expect(engine.isPlaying == false, "reset must not leave the UI claiming playback")
        #expect(engine.playbackStartFailed == true, "reset must surface the recoverable state")
        #expect(engine.isBuffering == false)
        #expect(engine.failedRetryCount == 0, "reset must clear the failed-item budget")
        #expect(engine.startWatchdogGeneration == nil, "reset must disarm the start watchdog")
    }

    /// Disarm clears every fencing field so no stale check can fire — the mechanism Stop and a new
    /// swap rely on to cancel a pending watchdog.
    @Test func disarmClearsWatchdogState() {
        let engine = AudioEngine.shared
        engine.startWatchdogGeneration = 99
        engine.startWatchdogSongId = "stale"
        engine.startWatchdogArmedAt = Date()
        engine.startWatchdogAttempts = 1

        engine.disarmStartWatchdog(reason: "test")

        #expect(engine.startWatchdogGeneration == nil)
        #expect(engine.startWatchdogSongId == nil)
        #expect(engine.startWatchdogArmedAt == nil)
        #expect(engine.startWatchdogAttempts == 0)
    }
}
