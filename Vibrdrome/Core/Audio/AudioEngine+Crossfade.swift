import AVFoundation
import Foundation
import os.log

private let crossfadeEngineLog = Logger(subsystem: "com.vibrdrome.app", category: "Audio")

// MARK: - Crossfade Playback

extension AudioEngine {

    /// Start playback using the crossfade dual-player topology
    func startCrossfadePlayback(url: URL) {
        tearDownObservers()
        clearLookahead()
        incrementGeneration()

        if !crossfadeController.isSetUp {
            crossfadeController.setup()
        }

        crossfadeController.loadOnActive(url: url)
        crossfadeController.activePlayer?.rate = playbackRate
        isCrossfading = false

        setupCrossfadeTimeObserver()

        if let item = crossfadeController.activePlayer?.currentItem {
            setupPropertyObservers(for: item, generation: generationValue)
            setupCrossfadeTrackEndObserver(for: item)
        }
    }

    /// Time observer for crossfade mode — detects when to begin crossfade
    func setupCrossfadeTimeObserver() {
        removeCurrentTimeObserver()

        let observerGeneration = generationValue
        let activeP = crossfadeController.activePlayer
        setTimeObserver(player: activeP)

        let observer = activeP?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self,
                      self.generationValue == observerGeneration else { return }
                self.currentTime = time.seconds
                if self.currentSong != nil {
                    NowPlayingManager.shared.updateElapsedTime(time.seconds)
                }
                self.autoScrobbleIfNeeded()
                self.checkCrossfadeTrigger()
            }
        }
        setTimeObserver(observer: observer)
    }

    /// Check if we should start crossfading to the next track
    func checkCrossfadeTrigger() {
        guard !isCrossfading,
              activeMode == .crossfade,
              crossfadeDuration > 0,
              duration > 0,
              currentRadioStation == nil else { return }

        let fadeDur = min(Double(crossfadeDuration), duration * 0.5)
        let fadeStart = duration - fadeDur
        guard fadeStart > 0, fadeDur > 0, currentTime >= fadeStart else { return }

        guard repeatMode != .one else { return }

        guard let nextIdx = nextSongIndex(), nextIdx < queue.count else { return }
        let nextSong = queue[nextIdx]
        let nextURL = resolveURL(for: nextSong)

        let nextRGFactor = computeReplayGainFactor(for: nextSong)

        isCrossfading = true
        crossfadeEngineLog.info("Starting crossfade to: \(nextSong.title)")

        crossfadeController.beginCrossfade(
            nextURL: nextURL,
            duration: fadeDur
        ) { [weak self] in
            guard let self else { return }
            self.handleCrossfadeComplete(
                nextSong: nextSong,
                nextIndex: nextIdx,
                replayGainFactor: nextRGFactor
            )
        }
    }

    /// Called when crossfade ramp completes
    func handleCrossfadeComplete(
        nextSong: Song,
        nextIndex: Int,
        replayGainFactor: Float
    ) {
        submitScrobbleIfNeeded()
        isCrossfading = false

        currentIndex = nextIndex
        currentSong = nextSong
        resetScrobbleState()
        currentTime = 0
        duration = 0
        setReplayGainFactor(replayGainFactor)

        tearDownObservers()
        incrementGeneration()
        setupCrossfadeTimeObserver()
        if let item = crossfadeController.activePlayer?.currentItem {
            setupPropertyObservers(for: item, generation: generationValue)
            setupCrossfadeTrackEndObserver(for: item)
        }

        applyEffectiveVolume()
        NowPlayingManager.shared.update(song: nextSong, isPlaying: true)

        scrobbleNowPlaying(songId: nextSong.id)
        refillRadioIfNeeded()
    }

    /// Track-end observer for crossfade mode (when track ends without crossfade trigger)
    func setupCrossfadeTrackEndObserver(for item: AVPlayerItem) {
        tearDownItemEndObserver()
        let observerGeneration = generationValue

        setItemEndObserver(
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self,
                          self.generationValue == observerGeneration else { return }
                    if !self.isCrossfading {
                        self.handleTrackEnd()
                    }
                }
            }
        )
    }
}
