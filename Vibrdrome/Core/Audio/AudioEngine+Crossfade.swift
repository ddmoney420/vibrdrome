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
        if let item = crossfadeController.activePlayer?.currentItem {
            applyEQTapIfNeeded(to: item)
            // Initial active item is the audible one → visualizer PCM source.
            EQTapProcessor.setVisualizerSource(for: item)
        }
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
                self.autoScrobbleIfNeeded()
                self.checkCrossfadeTrigger()
                self.checkPredownloadedSongNearEnd()
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

        // #89: base the fade point on effectiveDuration (max of AVPlayer/server durations), not the
        // raw AVPlayer item duration, which under-reports on some VBR/FLAC files and would start the
        // crossfade a few seconds early. effectiveDuration >= duration, so the fade can only move
        // later toward the true end. The `duration > 0` guard above still gates on a loaded item.
        let fadeDur = min(Double(crossfadeDuration), effectiveDuration * 0.5)
        let fadeStart = effectiveDuration - fadeDur
        guard fadeStart > 0, fadeDur > 0, currentTime >= fadeStart else { return }

        guard repeatMode == .off else { return }

        guard let nextIdx = nextSongIndex(), nextIdx < queue.count else { return }
        let nextSong = queue[nextIdx]
        let nextURL = resolveURL(for: nextSong)

        let nextRGFactor = computeReplayGainFactor(for: nextSong)

        isCrossfading = true
        crossfadeEngineLog.info("Starting crossfade to: \(nextSong.title)")

        // Advance logical playback state immediately so that NowPlaying, the
        // predownload window, the shuffle cache, and radio refill all see the
        // incoming track for the full duration of the fade — not just after it
        // completes.
        if shuffleEnabled, let outgoing = currentSong {
            shufflePlayHistory.append(outgoing)
            if shufflePlayHistory.count > Self.maxShufflePlayHistory {
                shufflePlayHistory.removeFirst()
            }
        }
        currentIndex = nextIdx
        currentSong = nextSong
        setReplayGainFactor(nextRGFactor)
        NowPlayingManager.shared.update(song: nextSong, isPlaying: true)
        scrobbleNowPlaying(songId: nextSong.id)
        startPredownloadIfNeeded(startIndex: nextIdx, queue: queue)
        refillRadioIfNeeded()

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
        startIncomingCrossfadeTrack()
    }

    /// Attach the EQ tap to the incoming crossfade track (always — passthrough
    /// when EQ is off, so audio is unchanged) and start it playing. Designates the
    /// incoming item as the single visualizer PCM source so only it feeds the
    /// ring during the overlap (no double-feed with the outgoing track).
    private func startIncomingCrossfadeTrack() {
        let inactivePlayer = crossfadeController.inactivePlayer
        guard let item = inactivePlayer?.currentItem else {
            inactivePlayer?.play()
            return
        }
        EQTapProcessor.setVisualizerSource(for: item)
        let gen = generation
        Task {
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                guard self.generation == gen, let track = tracks.first else {
                    inactivePlayer?.play()
                    return
                }
                if let mix = EQTapProcessor.createAudioMix(for: item, track: track) {
                    item.audioMix = mix
                }
                inactivePlayer?.play()
            } catch {
                inactivePlayer?.play()
            }
        }
    }

    /// Called when crossfade ramp completes — logical state was already advanced
    /// at fade start; this only handles the audio observer handoff and time reset.
    func handleCrossfadeComplete(
        nextSong: Song,
        nextIndex: Int,
        replayGainFactor: Float
    ) {
        submitScrobbleIfNeeded()
        isCrossfading = false

        resetScrobbleState()
        currentTime = 0
        duration = 0

        tearDownObservers()
        incrementGeneration()
        setupCrossfadeTimeObserver()
        if let item = crossfadeController.activePlayer?.currentItem {
            // After the swap the active player IS the incoming track (already the
            // designated source); re-assert defensively to clear any stale token.
            EQTapProcessor.setVisualizerSource(for: item)
            setupPropertyObservers(for: item, generation: generationValue)
            setupCrossfadeTrackEndObserver(for: item)
        }

        applyEffectiveVolume()
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
