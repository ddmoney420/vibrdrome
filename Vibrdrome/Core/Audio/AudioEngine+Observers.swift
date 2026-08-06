import AVFoundation
import Combine
import Foundation
import MediaPlayer
import os.log

private let observerLog = Logger(subsystem: "com.vibrdrome.app", category: "Audio")

// MARK: - Observer Setup & Teardown

extension AudioEngine {

    func setupObservers(for item: AVPlayerItem) {
        let gen = generationValue
        setupTimeObserver(generation: gen)
        setupPropertyObservers(for: item, generation: gen)
        setupTrackEndObserver(for: item, generation: gen)
    }

    func setupTimeObserver(generation observerGeneration: Int) {
        setTimeObserver(player: gaplessPlayer)
        let observer = gaplessPlayer?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self,
                      self.generationValue == observerGeneration else { return }
                self.currentTime = time.seconds
                NowPlayingManager.shared.updateElapsedTime(time.seconds)
                self.autoScrobbleIfNeeded()
                self.checkPredownloadedSongNearEnd()
            }
        }
        setTimeObserver(observer: observer)
    }

    func setupPropertyObservers(
        for item: AVPlayerItem, generation observerGeneration: Int
    ) {
        setDurationObserver(item.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                guard let self, self.generationValue == observerGeneration else { return }
                if dur.isNumeric {
                    self.duration = dur.seconds
                    // Report the larger of AVPlayer/server durations to the lock screen
                    // and CarPlay so they don't show a short total (#58).
                    NowPlayingManager.shared.updateDuration(self.effectiveDuration)
                }
            })

        setBufferingObserver(item.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] empty in
                guard let self, self.generationValue == observerGeneration else { return }
                self.isBuffering = empty
                if empty { self.armStallRecovery(reason: "bufferEmpty") }
            })

        setStatusObserver(item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.generationValue == observerGeneration else { return }
                if status == .failed {
                    let errorDesc = item.error?.localizedDescription ?? "unknown"
                    observerLog.warning("Player item failed: \(errorDesc) — attempting resume retry")
                    // Auto-retry: reload and seek to where we were instead of restarting
                    if let song = self.currentSong {
                        let resumeTime = self.currentTime
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            guard self.generationValue == observerGeneration else { return }
                            self.play(song: song)
                            if resumeTime > 5 {
                                self.seek(to: resumeTime - 2) // Resume slightly before failure point
                            }
                        }
                    } else {
                        item.audioMix = nil
                        self.isPlaying = false
                        self.isBuffering = false
                    }
                }
            })

        setupStallRecoveryObservers(for: item, generation: observerGeneration)
    }

    func setupTrackEndObserver(
        for item: AVPlayerItem, generation observerGeneration: Int
    ) {
        let endItem = item
        setItemEndObserver(
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self,
                          self.generationValue == observerGeneration else { return }
                    self.handleItemDidPlayToEnd(endItem: endItem, generation: observerGeneration)
                }
            }
        )
    }

    /// Route an item's end-of-play to the correct advance path. When the queue player already
    /// promoted the next item, advance immediately. When it has a ready, queued lookahead but
    /// hasn't promoted it synchronously yet, wait for the actual promotion event rather than
    /// reloading an already-buffered track (the end-of-track race). Otherwise reload.
    func handleItemDidPlayToEnd(endItem: AVPlayerItem, generation observerGeneration: Int) {
        let currentIsEnd = (gaplessPlayer?.currentItem === endItem)
        let lookaheadQueued: Bool
        if let lookahead = lookaheadItem, let player = gaplessPlayer {
            lookaheadQueued = player.items().contains(lookahead)
        } else {
            lookaheadQueued = false
        }
        let lookaheadReady = (lookaheadItem?.status == .readyToPlay)

        switch GaplessAdvanceDecision.decide(
            currentItemIsEndItem: currentIsEnd, hasLookahead: hasLookahead,
            lookaheadQueued: lookaheadQueued, lookaheadReady: lookaheadReady) {
        case .autoAdvance:
            handleAutoAdvance()
        case .awaitPromotion:
            if let lookahead = lookaheadItem {
                awaitLookaheadPromotion(lookahead: lookahead, generation: observerGeneration)
            } else {
                handleTrackEnd()
            }
        case .reload:
            handleTrackEnd()
        }
    }

    /// Wait (event-driven) for `AVQueuePlayer` to promote `lookahead` to `currentItem`, then take
    /// the existing `handleAutoAdvance()` path. Falls back to the existing reload path if the
    /// promotion doesn't occur within `lookaheadPromotionTimeout`. The wait is cancelled if the
    /// item-end observer is torn down (replace / stop / skip / generation change).
    func awaitLookaheadPromotion(lookahead: AVPlayerItem, generation observerGeneration: Int) {
        guard let player = gaplessPlayer else { handleTrackEnd(); return }
        let promotion = player.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)
            .map { $0 === lookahead }
            .eraseToAnyPublisher()
        promotionWaiter.arm(
            promotion: promotion,
            timeoutSeconds: AudioEngine.lookaheadPromotionTimeout
        ) { [weak self] promoted in
            guard let self, self.generationValue == observerGeneration else { return }
            if promoted {
                self.handleAutoAdvance()
            } else {
                self.handleTrackEnd()
            }
        }
    }

    func setupLookaheadEndObserver(for item: AVPlayerItem) {
        removeLookaheadEndObserver()

        let observerGeneration = generationValue

        setLookaheadEndObserver(
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self,
                          self.generationValue == observerGeneration else { return }
                    self.handleTrackEnd()
                }
            }
        )
    }

    func tearDownObservers() {
        removeCurrentTimeObserver()
        tearDownItemEndObserver()
        tearDownPropertyObservers()
    }

    func tearDownItemEndObserver() {
        removeItemEndObserver()
    }

    func tearDownPropertyObservers() {
        disarmStallRecovery(reason: "teardown")
        clearPropertyObservers()
    }

    // MARK: - Stalled-Stream Auto-Recovery
    //
    // A network stall can park the player at `paused`/rate-0 even after the buffer refills,
    // leaving playback silently stuck (proven via diagnostics: WAITING → stalled → paused →
    // 40s buffered, playhead frozen). We re-issue playback ONLY when the app still intends to
    // play (`isPlaying`), the player is genuinely parked (`.paused`, not still `WAITING`), and
    // the buffer has recovered — never on a user/interruption pause (those clear `isPlaying`).
    // Shared `activePlayer` path → covers gapless and crossfade. Action is kill-switchable.

    /// Attach time-control / buffer-recovery observers to the active player+item.
    func setupStallRecoveryObservers(for item: AVPlayerItem, generation gen: Int) {
        guard let player = activePlayer else { return }
        stallItemHasPlayed = false   // fresh item — wait until it actually plays before arming

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.generationValue == gen else { return }
                self.handleTimeControlStatus(status)
            }.store(in: &stallObservers)

        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] likely in
                guard let self, self.generationValue == gen else { return }
                if likely, self.stallRecoveryArmed { self.scheduleStallRecoveryCheck() }
            }.store(in: &stallObservers)

        item.publisher(for: \.loadedTimeRanges)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.generationValue == gen else { return }
                if self.stallRecoveryArmed { self.scheduleStallRecoveryCheck() }
            }.store(in: &stallObservers)

        stallNotifToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generationValue == gen else { return }
                self.armStallRecovery(reason: "stalled")
            }
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .waitingToPlayAtSpecifiedRate:
            // Persistent waiting with ample buffer is a stuck state we override after a grace.
            if isPlaying { armStallRecovery(reason: "waiting"); scheduleStallRecoveryCheck() }
        case .paused:
            // Involuntary pause (a user pause clears `isPlaying` + disarms before this fires).
            if isPlaying { armStallRecovery(reason: "pausedAfterStall"); scheduleStallRecoveryCheck() }
        case .playing:
            stallItemHasPlayed = true   // a later not-playing transition is now a real stall
            if stallRecoveryArmed {
                if stallRecoveryAttempts > 0 {
                    recoveryEvent("RECOVERY.success after \(self.stallRecoveryAttempts) attempt(s)")
                } else {
                    recoveryEvent("RECOVERY.selfRecovered")   // short waiting resolved on its own
                }
                disarmStallRecovery(reason: "playing", silent: true)
            }
        @unknown default:
            break
        }
    }

    /// Lightweight production `RECOVERY.*` event (ships in Release) for diagnosing future stalls.
    func recoveryEvent(_ message: String) {
        observerLog.info("\(message, privacy: .public)")
    }

    func armStallRecovery(reason: String) {
        // Only a stall of an already-playing item — never initial buffering at track start.
        guard isPlaying, !stallRecoveryArmed, stallItemHasPlayed else { return }
        stallRecoveryArmed = true
        stallRecoveryAttempts = 0
        stallBufferAmpleSince = nil
        recoveryEvent("RECOVERY.armed reason=\(reason)")
    }

    /// (Re)schedule a recovery evaluation. Short debounce by default; the grace path reschedules
    /// with the remaining grace so a stuck WAITING is re-checked even if buffer updates stop.
    func scheduleStallRecoveryCheck(after delay: TimeInterval = 0.3) {
        pendingStallRecovery?.cancel()
        let gen = generationValue
        pendingStallRecovery = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 0.05)))
            guard let self, !Task.isCancelled, self.generationValue == gen else { return }
            self.attemptStallRecovery(generation: gen)
        }
    }

    private func attemptStallRecovery(generation gen: Int) {
        guard generationValue == gen, isPlaying, stallRecoveryArmed,
              let player = activePlayer, let item = player.currentItem else { return }
        // Act while genuinely not playing — either parked at .paused OR stuck WAITING. If it
        // resumed, the .playing handler already disarmed us.
        let status = player.timeControlStatus
        guard status == .paused || status == .waitingToPlayAtSpecifiedRate else { return }

        // Buffer must be clearly healthy before we override AVPlayer.
        let ahead = AudioEngine.bufferedAhead(in: item, current: player.currentTime().seconds)
        let ample = ahead >= AudioEngine.stallRecoveryBufferThreshold || item.isPlaybackLikelyToKeepUp
        guard ample else { stallBufferAmpleSince = nil; return }   // wait for the buffer to fill

        // Grace: give AVPlayer's normal short waiting time to self-recover before we force play.
        let now = Date()
        if stallBufferAmpleSince == nil { stallBufferAmpleSince = now }
        let ampleFor = now.timeIntervalSince(stallBufferAmpleSince ?? now)
        guard ampleFor >= AudioEngine.stallRecoveryGrace else {
            scheduleStallRecoveryCheck(after: AudioEngine.stallRecoveryGrace - ampleFor + 0.1)
            return
        }

        // Bound retries.
        guard stallRecoveryAttempts < AudioEngine.stallRecoveryMaxAttempts else {
            recoveryEvent("RECOVERY.giveUp after \(stallRecoveryAttempts) attempt(s)")
            disarmStallRecovery(reason: "giveUp", silent: true)
            return
        }
        // Anti-thrash throttle.
        if let last = lastStallRecoveryTime,
           now.timeIntervalSince(last) < AudioEngine.stallRecoveryMinInterval {
            scheduleStallRecoveryCheck(after: AudioEngine.stallRecoveryMinInterval)
            return
        }
        // Kill switch gates the ACTION, not the logging.
        guard stallAutoRecoveryEnabled else {
            recoveryEvent("RECOVERY.attempt suppressed (stallAutoRecoveryEnabled=false)")
            return
        }
        stallRecoveryAttempts += 1
        lastStallRecoveryTime = now
        let reason = status == .waitingToPlayAtSpecifiedRate ? "persistentWaiting" : "pausedAfterStall"
        recoveryEvent("RECOVERY.attempt #\(stallRecoveryAttempts) reason=\(reason) "
            + "aheadSec=\(String(format: "%.1f", ahead))")
        player.playImmediately(atRate: playbackRate)
        scheduleStallRecoveryWatchdog(generation: gen)
    }

    private func scheduleStallRecoveryWatchdog(generation gen: Int) {
        pendingStallRecovery?.cancel()
        pendingStallRecovery = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, self.generationValue == gen,
                  self.stallRecoveryArmed else { return }
            if self.activePlayer?.timeControlStatus == .playing {
                recoveryEvent("RECOVERY.success after \(self.stallRecoveryAttempts) attempt(s)")
                self.disarmStallRecovery(reason: "success", silent: true)
            } else if self.stallRecoveryAttempts < AudioEngine.stallRecoveryMaxAttempts {
                self.scheduleStallRecoveryCheck()   // retry/backoff
            } else {
                recoveryEvent("RECOVERY.giveUp after \(self.stallRecoveryAttempts) attempt(s)")
                self.disarmStallRecovery(reason: "giveUp", silent: true)
            }
        }
    }

    func disarmStallRecovery(reason: String, silent: Bool = false) {
        let wasArmed = stallRecoveryArmed
        stallRecoveryArmed = false
        stallRecoveryAttempts = 0
        lastStallRecoveryTime = nil
        stallBufferAmpleSince = nil
        pendingStallRecovery?.cancel()
        pendingStallRecovery = nil
        if wasArmed && !silent {
            recoveryEvent("RECOVERY.disarmed reason=\(reason)")
        }
    }

    // MARK: - Scrobbling

    func autoScrobbleIfNeeded() {
        // #90: use effectiveDuration (max of AVPlayer/server durations) for the 50% threshold. The
        // raw AVPlayer duration under-reports on some VBR/FLAC files, firing the scrobble a few
        // seconds early; effectiveDuration >= duration so the half-played point can only move later,
        // matching the "played >= half" rule more accurately. `duration > 0` still gates a loaded item.
        guard !isScrobbleSubmitted,
              duration > 0,
              currentTime > effectiveDuration * 0.5,
              let song = currentSong else { return }
        markScrobbleSubmitted()
        PersistenceController.shared.recordPlay(song: song)
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.scrobblingEnabled) {
            Task {
                do {
                    try await OfflineActionQueue.shared.scrobble(
                        id: song.id, submission: true
                    )
                } catch {
                    observerLog.error("Failed to scrobble submission: \(error)")
                }
            }
        }
        Task { await OfflineActionQueue.shared.listenBrainzScrobble(song: song) }
        Task { await OfflineActionQueue.shared.lastFmScrobble(song: song) }
    }

    func submitScrobbleIfNeeded() {
        guard let song = currentSong, !isScrobbleSubmitted, duration > 0 else { return }
        let played = activePlayer?.currentTime().seconds ?? currentTime
        // #90: effectiveDuration for the 50% threshold (see autoScrobbleIfNeeded). The 240s cap is
        // preserved unchanged.
        let threshold = min(240, effectiveDuration * 0.5)
        if played >= threshold {
            markScrobbleSubmitted()
            PersistenceController.shared.recordPlay(song: song)
            if UserDefaults.standard.bool(forKey: UserDefaultsKeys.scrobblingEnabled) {
                Task {
                    do {
                        try await OfflineActionQueue.shared.scrobble(
                            id: song.id, submission: true
                        )
                    } catch {
                        observerLog.error("Failed to scrobble on track end: \(error)")
                    }
                }
            }
            Task { await OfflineActionQueue.shared.listenBrainzScrobble(song: song) }
            Task { await OfflineActionQueue.shared.lastFmScrobble(song: song) }
        }
    }

    /// Fire-and-forget scrobble "now playing" notification
    func scrobbleNowPlaying(songId: String) {
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.scrobblingEnabled) {
            Task {
                do {
                    try await OfflineActionQueue.shared.scrobble(
                        id: songId, submission: false
                    )
                } catch {
                    observerLog.error("Failed to scrobble now-playing: \(error)")
                }
            }
        }
        if let song = currentSong {
            Task { await ListenBrainzClient.shared.submitNowPlaying(song: song) }
            Task { await LastFmClient.shared.updateNowPlaying(song: song) }
        }
        reportPlaybackState("starting", songId: songId, positionMs: 0)
    }

    /// Fire-and-forget OpenSubsonic playbackReport state update.
    func reportPlaybackState(_ state: String, songId: String? = nil, positionMs: Int? = nil) {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.playbackReportEnabled) else { return }
        let id = songId ?? currentSong?.id
        guard let id else { return }
        let posMs = positionMs ?? Int(currentTime * 1000)
        Task {
            do {
                try await AppState.shared.subsonicClient.reportPlayback(
                    mediaId: id, positionMs: posMs, state: state
                )
            } catch {
                observerLog.debug("reportPlayback(\(state)) failed: \(error)")
            }
        }
    }
}
