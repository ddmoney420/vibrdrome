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
                self.autoScrobbleIfNeeded()
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
                    NowPlayingManager.shared.updateDuration(dur.seconds)
                }
            })

        setBufferingObserver(item.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] empty in
                guard let self, self.generationValue == observerGeneration else { return }
                self.isBuffering = empty
            })

        setStatusObserver(item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.generationValue == observerGeneration else { return }
                if status == .failed {
                    observerLog.warning("Player item failed — attempting auto-retry")
                    // Auto-retry: reload the current track instead of giving up
                    if let song = self.currentSong {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            guard self.generationValue == observerGeneration else { return }
                            self.play(song: song)
                        }
                    } else {
                        item.audioMix = nil
                        self.isPlaying = false
                        self.isBuffering = false
                    }
                }
            })
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

                    if self.gaplessPlayer?.currentItem !== endItem
                        && self.hasLookahead {
                        self.handleAutoAdvance()
                    } else {
                        self.handleTrackEnd()
                    }
                }
            }
        )
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
        clearPropertyObservers()
    }

    // MARK: - Scrobbling

    func autoScrobbleIfNeeded() {
        guard !isScrobbleSubmitted,
              duration > 0,
              currentTime > duration * 0.5,
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
    }

    func submitScrobbleIfNeeded() {
        guard let song = currentSong, !isScrobbleSubmitted, duration > 0 else { return }
        let played = activePlayer?.currentTime().seconds ?? currentTime
        let threshold = min(240, duration * 0.5)
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
    }
}
