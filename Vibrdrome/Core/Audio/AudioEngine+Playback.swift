import AVFoundation
import Foundation
import MediaPlayer
import os.log
#if os(macOS)
import AppKit
#endif

// Free function so the MPMediaItemArtwork closure doesn't inherit @MainActor isolation.
// MPMediaItemArtwork calls its requestHandler on a background queue.
#if os(iOS)
private func makeRadioArtwork(from image: UIImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
}
#else
private func makeRadioArtwork(from image: NSImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
}
#endif

private let playbackLog = Logger(subsystem: "com.vibrdrome.app", category: "Audio")

// MARK: - Playback Control

extension AudioEngine {

    func hashSongs(_ newQueue: [Song]) -> Int {
        var hasher = Hasher()
        for song in newQueue {
            hasher.combine(song.title)
        }
        return hasher.finalize()
    }
    
    func play(song: Song, from newQueue: [Song]? = nil, at index: Int = 0) {
        // UI testing: update observable state only, skip AVPlayer operations
        if isUITesting {
            playForUITesting(song: song, newQueue: newQueue, index: index)
            return
        }

        var hv = 0
        if (newQueue != nil) {
            hv = hashSongs(newQueue!)
        }
        playbackLog.debug("aldebug: play called \(song.title) \(index) queue:\(hv)")
        
        submitScrobbleIfNeeded()

        if isCrossfading {
            incrementGeneration()
            crossfadeController.forceComplete()
            isCrossfading = false
        }

        updateQueue(for: song, newQueue: newQueue, index: index)

        let isNewTrack = currentSong?.id != song.id
        currentSong = song
        currentRadioStation = nil
        // Only clear playingFromContext when a NEW queue is loaded,
        // not when advancing within the same queue (next/previous)
        if newQueue != nil {
            playingFromContext = nil
        }
        scrobbleSubmitted = false
        if isNewTrack { repeatOneUsed = false }
        trackStartTime = Date()
        currentTime = 0
        duration = 0
        isSeeking = false

        let newMode = selectMode(for: song)
        if newMode != activeMode {
            tearDownCurrentMode()
            activeMode = newMode
        }

        let url = resolveURL(for: song)
        currentReplayGainFactor = computeReplayGainFactor(for: song)

        switch activeMode {
        case .gapless:
            replacePlayerItem(with: url)
            applyEffectiveVolume()
            gaplessPlayer?.rate = playbackRate
            prepareLookahead()
        case .crossfade:
            startCrossfadePlayback(url: url)
            applyEffectiveVolume()
        }

        isPlaying = true
        NowPlayingManager.shared.update(song: song, isPlaying: true)
        scrobbleNowPlaying(songId: song.id)
        
        if (newQueue == nil) {
            startPredownloadIfNeeded(startIndex: currentIndex, queue: queue)
        } else {
            startPredownloadIfNeeded(startIndex: index, queue: newQueue!)
        }
    }

    /// UI testing path for play — updates observable state without AVPlayer
    private func playForUITesting(song: Song, newQueue: [Song]?, index: Int) {
        if let newQueue {
            queue = newQueue
            currentIndex = newQueue.isEmpty ? 0 : min(index, newQueue.count - 1)
        } else {
            queue = [song]
            currentIndex = 0
        }
        currentSong = song
        currentRadioStation = nil
        isPlaying = true
        duration = Double(song.duration ?? 180)
        currentTime = 0
    }

    /// Update the queue and current index for a new play request
    private func updateQueue(for song: Song, newQueue: [Song]?, index: Int) {
        if let newQueue {
            queue = newQueue
            currentIndex = newQueue.isEmpty ? 0 : min(index, newQueue.count - 1)
            shufflePlayCount = 0
        } else if queue.isEmpty {
            queue = [song]
            currentIndex = 0
        } else if let existingIndex = queue.firstIndex(where: { $0.id == song.id }) {
            currentIndex = existingIndex
        } else {
            queue = [song]
            currentIndex = 0
        }
    }
    
    func insertSongNext(for song: Song, at atSong: Int) {
        guard atSong >= 0 && atSong <= queue.count else {
            playbackLog.debug("aldebug: insertSongNext: Invalid index \(atSong) for queue of size \(self.queue.count)")
            return
        }
        
        // Insert song at specified index
        queue.insert(song, at: atSong)
        
        playbackLog.debug("aldebug: insertSongNext: Inserted '\(song.title)' at index \(atSong), current index now \(self.currentIndex)")
    }

    func playRadio(station: InternetRadioStation) {
        if isUITesting {
            currentSong = nil
            currentRadioStation = station
            queue.removeAll()
            currentIndex = 0
            isPlaying = true
            return
        }

        submitScrobbleIfNeeded()
        guard let url = URL(string: station.streamUrl) else { return }

        if activeMode != .gapless {
            tearDownCurrentMode()
            activeMode = .gapless
        }

        currentSong = nil
        currentRadioStation = station
        queue.removeAll()
        currentIndex = 0
        scrobbleSubmitted = false
        currentTime = 0
        duration = 0
        clearLookahead()

        replacePlayerItem(with: url)
        gaplessPlayer?.play()
        isPlaying = true

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = station.name
        info[MPMediaItemPropertyArtist] = "Internet Radio"
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        // Clear previous artwork immediately to prevent stale album art
        info[MPMediaItemPropertyArtwork] = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        loadRadioArtwork(for: station)
    }

    /// Load radio station artwork for lock screen
    private func loadRadioArtwork(for station: InternetRadioStation) {
        guard let artId = station.radioCoverArtId else { return }
        let stationId = station.id
        let artURL = AppState.shared.subsonicClient.coverArtURL(id: artId, size: 600)
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: artURL),
                  self.currentRadioStation?.id == stationId else { return }
            #if os(iOS)
            guard let image = UIImage(data: data) else { return }
            #else
            guard let image = NSImage(data: data) else { return }
            #endif
            let artwork = makeRadioArtwork(from: image)
            var nowInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            nowInfo[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowInfo
        }
    }

    func pause() {
        if isUITesting { isPlaying = false; return }
        activePlayer?.pause()
        isPlaying = false
        NowPlayingManager.shared.updatePlaybackState(isPlaying: false, elapsed: currentTime)
    }

    func resume() {
        if isUITesting { isPlaying = true; return }

        // Reactivate audio session (may have been deactivated by phone call or other interruption)
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            playbackLog.error("Failed to reactivate audio session: \(error)")
        }
        #endif

        // Cold start: no player loaded (e.g. restored from saved queue).
        // Route through play()/playRadio() for full setup.
        if gaplessPlayer == nil {
            if let station = currentRadioStation {
                playRadio(station: station)
                return
            }
            if let song = currentSong {
                let savedTime = currentTime
                play(song: song)
                if savedTime > 1 { seek(to: savedTime) }
                return
            }
        }

        switch activeMode {
        case .gapless:
            resumeGaplessMode()
        case .crossfade:
            resumeCrossfadeMode()
        }
        isPlaying = true
        NowPlayingManager.shared.updatePlaybackState(isPlaying: true, elapsed: currentTime)
    }

    private func resumeGaplessMode() {
        let itemNeedsReload = gaplessPlayer?.currentItem == nil
            || gaplessPlayer?.currentItem?.status == .failed
        if let song = currentSong, itemNeedsReload {
            let savedTime = currentTime
            let url = resolveURL(for: song)
            replacePlayerItem(with: url)
            if savedTime > 0 { seek(to: savedTime) }
            prepareLookahead()
        } else if eqEnabled, let item = gaplessPlayer?.currentItem {
            // Reapply EQ tap after interruption to reset stale delay buffers
            applyEQTapIfNeeded(to: item)
        }
        gaplessPlayer?.rate = playbackRate
    }

    private func resumeCrossfadeMode() {
        let itemNeedsReload = crossfadeController.activePlayer?.currentItem == nil
            || crossfadeController.activePlayer?.currentItem?.status == .failed
        if let song = currentSong, itemNeedsReload {
            let savedTime = currentTime
            let url = resolveURL(for: song)
            crossfadeController.loadOnActive(url: url)
            if let item = crossfadeController.activePlayer?.currentItem {
                applyEQTapIfNeeded(to: item)
            }
            if savedTime > 0 {
                let cmTime = CMTime(seconds: savedTime, preferredTimescale: 1000)
                crossfadeController.activePlayer?.seek(to: cmTime)
            }
        } else if eqEnabled, let item = crossfadeController.activePlayer?.currentItem {
            // Reapply EQ tap after interruption to reset stale delay buffers
            applyEQTapIfNeeded(to: item)
        }
        crossfadeController.activePlayer?.rate = playbackRate
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func next() {
        guard !queue.isEmpty else { return }
        playbackLog.debug("aldebug: next called \(self.currentIndex)")
        submitScrobbleIfNeeded()

        if isCrossfading {
            incrementGeneration()
            crossfadeController.forceComplete()
            isCrossfading = false
        }

        // Manual next always advances — reset repeat-one state
        repeatOneUsed = false
        guard advanceIndex(), currentIndex < queue.count else { return }
        play(song: queue[currentIndex])
        refillRadioIfNeeded()
    }

    func previous() {
        if !isPlaying && currentTime > 0 && duration > 0 && currentTime >= duration - 1 {
            // Paused at end of track — go to previous track
        } else if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        if currentIndex == 0 {
            seek(to: 0)
            return
        } else {
            currentIndex -= 1
        }
        play(song: queue[currentIndex])
    }

    func seek(to time: TimeInterval) {
        // Use song metadata duration as fallback when AVPlayer hasn't reported yet
        let effectiveDuration = duration > 0 ? duration : Double(currentSong?.duration ?? 0)
        guard effectiveDuration > 0 || time == 0 else { return }
        let clampedTime = max(0, min(time, effectiveDuration))

        // Cancel any in-progress crossfade ramp on seek
        if isCrossfading {
            crossfadeController.forceComplete()
            isCrossfading = false
            tearDownObservers()
            generation += 1
            setupCrossfadeTimeObserver()
            if let item = crossfadeController.activePlayer?.currentItem {
                setupPropertyObservers(for: item, generation: generation)
                setupCrossfadeTrackEndObserver(for: item)
            }
        }

        guard let player = activePlayer else { return }
        let wasPlaying = isPlaying
        let rate = playbackRate
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 1000)
        player.seek(
            to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = clampedTime
                NowPlayingManager.shared.updateElapsedTime(clampedTime)
                // Restore playback rate — AVPlayer can reset rate after seek
                if wasPlaying && player.rate == 0 {
                    player.rate = rate
                }
            }
        }
        // Update time immediately so UI doesn't show stale value
        currentTime = clampedTime
    }

    func stop() {
        if isUITesting {
            isPlaying = false
            currentSong = nil
            currentRadioStation = nil
            currentTime = 0
            duration = 0
            return
        }
        submitScrobbleIfNeeded()
        tearDownCurrentMode()
        activeMode = .gapless
        stopRadioMode()
        isCrossfading = false
        isPlaying = false
        currentSong = nil
        currentRadioStation = nil
        currentTime = 0
        duration = 0
        NowPlayingManager.shared.clear()
    }

    func restartCurrentTrack() {
        trackStartTime = Date()
        seekInternal(to: 0) { [weak self] in
            self?.scrobbleSubmitted = false
            self?.activePlayer?.play()
        }
    }

    func seekInternal(
        to time: TimeInterval, completion: (() -> Void)? = nil
    ) {
        guard let player = activePlayer else { completion?(); return }
        let rate = playbackRate
        let wasPlaying = isPlaying
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        nonisolated(unsafe) let safeCompletion = completion
        currentTime = time
        player.seek(
            to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time
                NowPlayingManager.shared.updateElapsedTime(time)
                if wasPlaying && player.rate == 0 {
                    player.rate = rate
                }
                safeCompletion?()
            }
        }
    }

    // MARK: - Index Advancement

    func advanceIndex() -> Bool {
        if shuffleEnabled { return advanceShuffleIndex() }
        currentIndex += 1
        if currentIndex >= queue.count {
            if isRadioMode {
                currentIndex = queue.count - 1
                refillRadioIfNeeded()
                return false
            } else {
                currentIndex = queue.count - 1
                // Auto-continue with similar songs instead of stopping
                autoSuggestMore()
                return false
            }
        }
        return true
    }

    func advanceShuffleIndex() -> Bool {
        if queue.count <= 1 {
            if repeatMode == .all {
                seekInternal(to: 0) { [weak self] in self?.scrobbleSubmitted = false }
                trackStartTime = Date()
                activePlayer?.play()
            } else {
                pause()
            }
            return false
        }
        if repeatMode == .off {
            shufflePlayCount += 1
            if shufflePlayCount >= queue.count {
                shufflePlayCount = 0
                pause()
                return false
            }
        }
        currentIndex = smartShuffleNextIndex()
        return true
    }

    func handleTrackEnd() {
        SleepTimer.shared.trackDidEnd()
        if !isPlaying { return }

        switch repeatMode {
        case .all:
            handleTrackEndRepeatAll()
        case .one:
            handleTrackEndRepeatOne()
        case .off:
            next()
        }
    }

    private func handleTrackEndRepeatAll() {
        // Loop entire queue — advance to next, wrap to beginning if at end
        if currentIndex + 1 >= queue.count {
            currentIndex = 0
            guard let song = queue.first else { return }
            play(song: song)
        } else {
            next()
        }
    }

    private func handleTrackEndRepeatOne() {
        // Repeat once then advance
        if !repeatOneUsed {
            guard let song = currentSong else { return }
            repeatOneUsed = true
            play(song: song)
        } else {
            repeatOneUsed = false
            if isCrossfading {
                incrementGeneration()
                crossfadeController.forceComplete()
                isCrossfading = false
            }
            guard advanceIndex() else { return }
            play(song: queue[currentIndex])
            refillRadioIfNeeded()
        }
    }

    func handleAutoAdvance() {
        playbackLog.debug("aldebug: handleAutoAdvance called")
        submitScrobbleIfNeeded()

        guard let nextIndex = lookaheadIndex, nextIndex < queue.count else {
            playbackLog.warning("Auto-advance but no valid lookahead index")
            return
        }

        currentIndex = nextIndex
        let nextSong = queue[currentIndex]
        currentSong = nextSong
        scrobbleSubmitted = false
        trackStartTime = Date()
        currentTime = 0
        duration = 0
        isSeeking = false

        removeLookaheadEndObserver()
        lookaheadItem = nil
        lookaheadSongId = nil
        lookaheadIndex = nil

        tearDownPropertyObservers()
        tearDownItemEndObserver()
        if let item = gaplessPlayer?.currentItem {
            setupPropertyObservers(for: item, generation: generation)
            setupTrackEndObserver(for: item, generation: generation)
        }

        currentReplayGainFactor = computeReplayGainFactor(for: nextSong)
        applyEffectiveVolume()

        NowPlayingManager.shared.update(song: nextSong, isPlaying: true)
        prepareLookahead()
        scrobbleNowPlaying(songId: nextSong.id)
        refillRadioIfNeeded()
        playbackLog.info("Gapless auto-advance to: \(nextSong.title) (index \(nextIndex))")
        startPredownloadIfNeeded(startIndex: currentIndex, queue: queue)
    }

    /// Jump to a specific index in the existing queue without replacing it.
    /// Unlike play(song:from:at:), this preserves the full queue intact.
    func skipToIndex(_ index: Int) {
        guard index >= 0, index < queue.count else { return }
        let song = queue[index]
        currentIndex = index
        currentSong = song
        currentRadioStation = nil
        scrobbleSubmitted = false
        repeatOneUsed = false
        trackStartTime = Date()
        currentTime = 0
        duration = 0

        let url = resolveURL(for: song)
        replacePlayerItem(with: url)
        activePlayer?.play()
        isPlaying = true

        NowPlayingManager.shared.update(song: song, isPlaying: true)
        scrobbleNowPlaying(songId: song.id)
    }

    /// Auto-suggest similar songs when the queue runs out
    func autoSuggestMore() {
        guard !isAutoSuggesting else { return }
        guard let lastSong = queue.last else {
            pause()
            return
        }
        isAutoSuggesting = true
        Task { @MainActor in
            defer { self.isAutoSuggesting = false }
            do {
                let client = AppState.shared.subsonicClient
                let similar = try await client.getSimilarSongs(id: lastSong.id, count: 10)
                let existingIds = Set(queue.map(\.id))
                let newSongs = similar.filter { !existingIds.contains($0.id) }
                guard !newSongs.isEmpty else {
                    // Fallback to random songs
                    let random = try await client.getRandomSongs(size: 10)
                    let filtered = random.filter { !existingIds.contains($0.id) }
                    guard !filtered.isEmpty else { pause(); return }
                    for song in filtered { addToQueue(song) }
                    next()
                    return
                }
                for song in newSongs { addToQueue(song) }
                next()
            } catch {
                pause()
            }
        }
    }
}
