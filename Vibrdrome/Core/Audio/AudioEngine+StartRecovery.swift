import AVFoundation
import Foundation

/// What the track-start watchdog should do given the current transport state. Pure and testable —
/// no player, no timers.
enum StartWatchdogDecision: Equatable {
    case disarm             // ready or playing — the start blind spot is closed
    case deferToFailure     // item is `.failed` — the existing item-status retry owns this
    case recover            // rebuild the intended item (bounded by attempts)
    case wait(TimeInterval) // re-check after this delay
    case giveUp             // attempts exhausted — fail honestly
}

/// The transport facts the decision needs. Generation / song / isPlaying fencing is the caller's
/// job; by the time this is consulted we already still intend to play the armed song.
struct StartWatchdogState: Equatable {
    var hasItem: Bool
    var itemStatus: AVPlayerItem.Status?   // nil when there is no current item
    var noItemToPlay: Bool                 // waiting with reason == .noItemToPlayReason
    var isPlayingNow: Bool                 // timeControlStatus == .playing
    var elapsed: TimeInterval              // since this attempt's grace window opened
    var attempts: Int                      // rebuilds already performed for the intended song
}

extension AudioEngine {

    /// Pure policy: closes the proven initial-start blind spot without touching the mid-playback
    /// stall recovery. A missing item / `noItemToPlay` is acted on fast; an item stuck `.unknown`
    /// gets a patient grace (slow cellular is legitimate); `.failed` defers to the existing retry;
    /// `ready`/`playing` disarms.
    static func startWatchdogDecision(_ state: StartWatchdogState) -> StartWatchdogDecision {
        if state.isPlayingNow { return .disarm }
        if state.itemStatus == .failed { return .deferToFailure }
        if state.itemStatus == .readyToPlay { return .disarm }
        // Not playing, not failed, not ready → a missing item or one stuck `.unknown`.
        let missing = !state.hasItem || state.noItemToPlay
        let grace = missing ? startWatchdogNoItemGrace : startWatchdogUnknownGrace
        if state.elapsed + 0.001 >= grace {
            return state.attempts < startWatchdogMaxAttempts ? .recover : .giveUp
        }
        return .wait(grace - state.elapsed)
    }

    /// Mandatory fencing: a watchdog may act only on the exact generation + intended song it armed
    /// for, and only while we still intend to play. Pure so the race property (a watchdog armed for
    /// song A must never touch song B after a rapid replacement) is deterministically testable.
    static func startWatchdogPassesFence(capturedGeneration: Int?, currentGeneration: Int,
                                         capturedSongId: String?, currentSongId: String?,
                                         isPlaying: Bool) -> Bool {
        guard let capturedGeneration, capturedGeneration == currentGeneration,
              let capturedSongId, currentSongId == capturedSongId, isPlaying else { return false }
        return true
    }

    // MARK: - Arm / disarm

    /// Arm for a freshly-swapped legacy item. Call after `replacePlayerItem` in the gapless swap.
    func armStartWatchdog(songId: String) {
        armStartWatchdog(songId: songId, attempt: 0)
    }

    private func armStartWatchdog(songId: String, attempt: Int) {
        startWatchdogTask?.cancel()
        startWatchdogGeneration = generationValue
        startWatchdogSongId = songId
        startWatchdogArmedAt = Date()
        startWatchdogAttempts = attempt
        #if DEBUG
        PlaybackEventLog.record("START.armed gen=\(generationValue) attempt=\(attempt)")
        #endif
        scheduleStartWatchdogCheck(after: Self.startWatchdogNoItemGrace)
    }

    /// Cancel any pending watchdog and clear its state. Safe to call when nothing is armed.
    func disarmStartWatchdog(reason: String) {
        guard startWatchdogTask != nil || startWatchdogGeneration != nil else { return }
        startWatchdogTask?.cancel()
        startWatchdogTask = nil
        startWatchdogGeneration = nil
        startWatchdogSongId = nil
        startWatchdogArmedAt = nil
        startWatchdogAttempts = 0
        #if DEBUG
        PlaybackEventLog.record("START.disarmed reason=\(reason)")
        #endif
    }

    private func scheduleStartWatchdogCheck(after delay: TimeInterval) {
        startWatchdogTask?.cancel()
        let gen = startWatchdogGeneration
        startWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 0.05)))
            guard let self, !Task.isCancelled, self.startWatchdogGeneration == gen else { return }
            self.evaluateStartWatchdog()
        }
    }

    // MARK: - Evaluate / recover / give up

    private func evaluateStartWatchdog() {
        // Fencing (mandatory): act only on the exact generation + intended song we armed for, and
        // only while we still intend to play. A watchdog armed for song A must never touch song B.
        guard Self.startWatchdogPassesFence(
                capturedGeneration: startWatchdogGeneration, currentGeneration: generationValue,
                capturedSongId: startWatchdogSongId, currentSongId: currentSong?.id,
                isPlaying: isPlaying),
              let songId = startWatchdogSongId, let armedAt = startWatchdogArmedAt else {
            disarmStartWatchdog(reason: "fenced-out")
            return
        }

        let player = gaplessPlayer
        let item = player?.currentItem
        // The rawValue is the exact string the device reports (verified in the field capture); the
        // Swift constant name varies by SDK, so match the rawValue to stay robust.
        let noItemToPlay = player?.reasonForWaitingToPlay?.rawValue == "AVPlayerWaitingWithNoItemToPlayReason"
        let state = StartWatchdogState(
            hasItem: item != nil,
            itemStatus: item?.status,
            noItemToPlay: noItemToPlay,
            isPlayingNow: player?.timeControlStatus == .playing,
            elapsed: Date().timeIntervalSince(armedAt),
            attempts: startWatchdogAttempts)

        switch Self.startWatchdogDecision(state) {
        case .disarm:
            disarmStartWatchdog(reason: "started")
        case .deferToFailure:
            disarmStartWatchdog(reason: "failed->existingRetry")
        case .wait(let delay):
            scheduleStartWatchdogCheck(after: delay)
        case .recover:
            recoverStart(songId: songId, state: state)
        case .giveUp:
            giveUpStart(state: state)
        }
    }

    private func recoverStart(songId: String, state: StartWatchdogState) {
        guard let song = currentSong, song.id == songId, isPlaying,
              startWatchdogGeneration == generationValue else {
            disarmStartWatchdog(reason: "fenced-out")
            return
        }
        // Respect the shared auto-recovery kill switch; if off, fail honestly rather than rebuild.
        guard stallAutoRecoveryEnabled else {
            #if DEBUG
            PlaybackEventLog.record("START.recover suppressed (stallAutoRecoveryEnabled=false)")
            #endif
            giveUpStart(state: state)
            return
        }
        let nextAttempt = startWatchdogAttempts + 1
        let missing = !state.hasItem || state.noItemToPlay
        recoveryEvent("START.recover attempt #\(nextAttempt) missing=\(missing)")
        #if DEBUG
        PlaybackEventLog.record("START.recover attempt=\(nextAttempt) missing=\(missing)")
        #endif
        // Rebuild the intended item. `replacePlayerItem` bumps the generation and installs fresh
        // observers; restore rate/volume exactly as the normal swap does, then re-arm under the new
        // generation for the same song so fencing continues to hold.
        let url = resolveURL(for: song)
        replacePlayerItem(with: url)
        applyEffectiveVolume()
        gaplessPlayer?.rate = playbackRate
        prepareLookahead()
        armStartWatchdog(songId: song.id, attempt: nextAttempt)
    }

    private func giveUpStart(state: StartWatchdogState) {
        recoveryEvent("START.giveUp after \(startWatchdogAttempts) attempt(s)")
        #if DEBUG
        PlaybackEventLog.record(
            "START.giveUp hasItem=\(state.hasItem) "
            + "status=\(PlaybackStateDescribe.itemStatus(state.itemStatus)) "
            + "noItemToPlay=\(state.noItemToPlay)")
        #endif
        disarmStartWatchdog(reason: "giveUp")
        // Fail honestly: the UI must no longer claim playback is active.
        gaplessPlayer?.pause()
        isPlaying = false
        playbackStartFailed = true
        NowPlayingManager.shared.updatePlaybackState(isPlaying: false, elapsed: currentTime)
    }
}
