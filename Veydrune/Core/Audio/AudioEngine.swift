import AVFoundation
import Combine
import Foundation
import MediaPlayer
import Network
import Observation
import SwiftData

enum RepeatMode: Sendable {
    case off, all, one
}

@Observable
@MainActor
final class AudioEngine {
    static let shared = AudioEngine()

    // MARK: - State

    var isPlaying = false
    var currentSong: Song?
    var currentRadioStation: InternetRadioStation?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isBuffering = false
    var isSeeking = false

    // MARK: - Queue

    var queue: [Song] = []
    var currentIndex: Int = 0
    var shuffleEnabled = false
    var repeatMode: RepeatMode = .off
    private var shufflePlayCount = 0

    // MARK: - Private

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemEndObserver: Any?
    private var bufferingObserver: AnyCancellable?
    private var durationObserver: AnyCancellable?
    private var statusObserver: AnyCancellable?
    private var scrobbleSubmitted = false
    private var trackStartTime: Date?
    /// Monotonically increasing counter to detect stale observer callbacks
    private var generation: Int = 0
    /// Wall-clock time of last scrobble, used to cap repeat-one scrobbles
    private var lastScrobbleTime: Date?
    /// Network path monitor for bitrate selection
    private let networkMonitor = NWPathMonitor()
    private var isOnCellular = false

    private init() {
        AudioSessionManager.shared.configure()
        startNetworkMonitor()
    }

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnCellular = path.usesInterfaceType(.cellular)
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "com.veydrune.network"))
    }

    /// Returns the current maxBitRate based on network type and user settings.
    /// 0 means original/no limit.
    private var currentMaxBitRate: Int? {
        let defaults = UserDefaults.standard
        let key = isOnCellular ? "cellularMaxBitRate" : "wifiMaxBitRate"
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }

    // MARK: - Playback Control

    func play(song: Song, from newQueue: [Song]? = nil, at index: Int = 0) {
        // Scrobble previous track if needed
        submitScrobbleIfNeeded()

        if let newQueue {
            queue = newQueue
            currentIndex = newQueue.isEmpty ? 0 : min(index, newQueue.count - 1)
            shufflePlayCount = 0
        } else if queue.isEmpty {
            // A6: play(song:) without queue — create a single-item queue
            queue = [song]
            currentIndex = 0
        } else if let existingIndex = queue.firstIndex(where: { $0.id == song.id }) {
            // Song exists in current queue — update currentIndex to match
            currentIndex = existingIndex
        } else {
            // Song not in queue — replace queue with single item
            queue = [song]
            currentIndex = 0
        }

        currentSong = song
        currentRadioStation = nil
        scrobbleSubmitted = false
        trackStartTime = Date()
        // A5/A7: Reset stale time/duration from previous track or radio
        currentTime = 0
        duration = 0

        let url = resolveURL(for: song)
        replacePlayerItem(with: url)

        player?.play()
        isPlaying = true

        NowPlayingManager.shared.update(song: song, isPlaying: true)

        // Scrobble "now playing"
        if UserDefaults.standard.bool(forKey: "scrobblingEnabled") {
            Task {
                try? await AppState.shared.subsonicClient.scrobble(id: song.id, submission: false)
            }
        }
    }

    func playRadio(station: InternetRadioStation) {
        submitScrobbleIfNeeded()

        guard let url = URL(string: station.streamUrl) else { return }

        currentSong = nil
        currentRadioStation = station
        queue.removeAll()
        currentIndex = 0
        scrobbleSubmitted = false
        currentTime = 0
        duration = 0

        replacePlayerItem(with: url)

        player?.play()
        isPlaying = true

        // Update Now Playing with station info
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = station.name
        info[MPMediaItemPropertyArtist] = "Internet Radio"
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func pause() {
        player?.pause()
        isPlaying = false
        NowPlayingManager.shared.updatePlaybackState(isPlaying: false, elapsed: currentTime)
    }

    func resume() {
        player?.play()
        isPlaying = true
        NowPlayingManager.shared.updatePlaybackState(isPlaying: true, elapsed: currentTime)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func next() {
        guard !queue.isEmpty else { return }

        submitScrobbleIfNeeded()

        if repeatMode == .one {
            // Restart same track, reset scrobble after seek completes (A2)
            trackStartTime = Date()
            seekInternal(to: 0) { [weak self] in
                self?.scrobbleSubmitted = false
                self?.player?.play()
            }
            return
        }

        if shuffleEnabled {
            // A3: Single-item queue with shuffle — don't tear down, just restart
            if queue.count <= 1 {
                if repeatMode == .all {
                    seekInternal(to: 0) { [weak self] in
                        self?.scrobbleSubmitted = false
                    }
                    trackStartTime = Date()
                    player?.play()
                } else {
                    pause()
                }
                return
            }
            // Shuffle + repeat off: stop after playing queue.count songs
            if repeatMode == .off {
                shufflePlayCount += 1
                if shufflePlayCount >= queue.count {
                    shufflePlayCount = 0
                    pause()
                    return
                }
            }
            var newIndex = Int.random(in: 0..<(queue.count - 1))
            if newIndex >= currentIndex { newIndex += 1 }
            currentIndex = newIndex
        } else {
            currentIndex += 1
            if currentIndex >= queue.count {
                if repeatMode == .all {
                    currentIndex = 0
                } else {
                    currentIndex = queue.count - 1
                    pause()
                    return
                }
            }
        }

        play(song: queue[currentIndex])
    }

    func previous() {
        // A4: At end-of-queue (paused, at end), go to previous track directly
        if !isPlaying && currentTime > 0 && duration > 0 && currentTime >= duration - 1 {
            // Paused at end of track — go to previous track
        } else if currentTime > 3 {
            // If >3 seconds in, restart current track
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        if currentIndex == 0 {
            if repeatMode == .all {
                currentIndex = queue.count - 1
            } else {
                seek(to: 0)
                return
            }
        } else {
            currentIndex -= 1
        }
        play(song: queue[currentIndex])
    }

    func seek(to time: TimeInterval) {
        guard player != nil else { return }
        // A8: If duration is 0, only allow seeking to 0 (for restarts)
        guard duration > 0 || time == 0 else { return }
        let clampedTime = max(0, min(time, duration > 0 ? duration : 0))
        // A1: Set isSeeking so time observer doesn't fight
        isSeeking = true
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 1000)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = clampedTime
                NowPlayingManager.shared.updateElapsedTime(clampedTime)
                self.isSeeking = false
            }
        }
    }

    func stop() {
        submitScrobbleIfNeeded()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
        currentSong = nil
        currentRadioStation = nil
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Shuffle / Repeat

    func toggleShuffle() {
        shuffleEnabled.toggle()
        shufflePlayCount = 0
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: - Queue Management

    var upNext: [Song] {
        guard !queue.isEmpty, currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    func addToQueue(_ song: Song) {
        queue.append(song)
    }

    func addToQueueNext(_ song: Song) {
        queue.insert(song, at: min(currentIndex + 1, queue.count))
    }

    func removeFromQueue(at index: Int) {
        let absoluteIndex = currentIndex + 1 + index
        // A8: Guard negative and out-of-bounds
        guard absoluteIndex > currentIndex, absoluteIndex < queue.count else { return }
        queue.remove(at: absoluteIndex)
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard currentIndex + 1 < queue.count else { return }
        var upNextSlice = Array(queue[(currentIndex + 1)...])
        upNextSlice.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange((currentIndex + 1)..., with: upNextSlice)
    }

    func clearQueue() {
        let current = currentIndex < queue.count ? queue[currentIndex] : nil
        queue.removeAll()
        if let current {
            queue.append(current)
            currentIndex = 0
        } else {
            // A6: No valid current — stop playback
            stop()
        }
    }

    // MARK: - Private Helpers

    private func resolveURL(for song: Song) -> URL {
        let modelContext = PersistenceController.shared.container.mainContext
        let songId = song.id
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
        )
        if let download = try? modelContext.fetch(descriptor).first {
            let fileURL = DownloadManager.absoluteURL(for: download.localFilePath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            // File gone from disk — clean up stale record
            modelContext.delete(download)
            try? modelContext.save()
        }
        return AppState.shared.subsonicClient.streamURL(id: song.id, maxBitRate: currentMaxBitRate)
    }

    /// Internal seek with completion handler — used by repeat-one and other internal paths
    private func seekInternal(to time: TimeInterval, completion: (() -> Void)? = nil) {
        guard player != nil else { completion?(); return }
        isSeeking = true
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        // Safe: completion is always invoked on @MainActor via the Task below
        nonisolated(unsafe) let safeCompletion = completion
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time
                NowPlayingManager.shared.updateElapsedTime(time)
                self.isSeeking = false
                safeCompletion?()
            }
        }
    }

    private func replacePlayerItem(with url: URL) {
        // Clean up old observers
        tearDownObservers()

        // Increment generation so stale callbacks are ignored
        generation += 1

        let item = AVPlayerItem(url: url)

        if player == nil {
            player = AVPlayer(playerItem: item)
            player?.automaticallyWaitsToMinimizeStalling = true
        } else {
            player?.replaceCurrentItem(with: item)
        }

        setupObservers(for: item)
    }

    private func setupObservers(for item: AVPlayerItem) {
        let observerGeneration = generation

        // Periodic time observer
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self,
                      self.generation == observerGeneration,
                      !self.isSeeking else { return }
                self.currentTime = time.seconds
                if self.currentSong != nil {
                    NowPlayingManager.shared.updateElapsedTime(time.seconds)
                }
                // Auto-scrobble at 50%
                if !self.scrobbleSubmitted,
                   self.duration > 0,
                   self.currentTime > self.duration * 0.5,
                   let song = self.currentSong {
                    self.scrobbleSubmitted = true
                    self.lastScrobbleTime = Date()
                    PersistenceController.shared.recordPlay(song: song)
                    if UserDefaults.standard.bool(forKey: "scrobblingEnabled") {
                        Task {
                            try? await AppState.shared.subsonicClient.scrobble(id: song.id, submission: true)
                        }
                    }
                }
            }
        }

        // Duration
        durationObserver = item.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                guard let self, self.generation == observerGeneration else { return }
                if dur.isNumeric {
                    self.duration = dur.seconds
                    NowPlayingManager.shared.updateDuration(dur.seconds)
                }
            }

        // Buffering
        bufferingObserver = item.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] empty in
                guard let self, self.generation == observerGeneration else { return }
                self.isBuffering = empty
            }

        // Status — detect failed streams (especially radio)
        statusObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.generation == observerGeneration else { return }
                if status == .failed {
                    self.isPlaying = false
                    self.isBuffering = false
                }
            }

        // Track ended — capture the item to verify it's still current
        let endItem = item
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.generation == observerGeneration,
                      self.player?.currentItem === endItem else { return }
                self.handleTrackEnd()
            }
        }
    }

    private func tearDownObservers() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
        durationObserver?.cancel()
        durationObserver = nil
        bufferingObserver?.cancel()
        bufferingObserver = nil
        statusObserver?.cancel()
        statusObserver = nil
    }

    private func handleTrackEnd() {
        if repeatMode == .one {
            // A3/A2: Cap repeat-one scrobbles — only scrobble if enough wall-clock time has passed
            trackStartTime = Date()
            seekInternal(to: 0) { [weak self] in
                guard let self else { return }
                if let lastScrobble = self.lastScrobbleTime,
                   Date().timeIntervalSince(lastScrobble) < max(self.duration, 30) {
                    // Don't reset scrobble flag — too soon, suppress re-scrobble
                } else {
                    self.scrobbleSubmitted = false
                }
                self.player?.play()
            }
        } else {
            next()
        }
    }

    private func submitScrobbleIfNeeded() {
        guard let song = currentSong, !scrobbleSubmitted, duration > 0 else { return }
        // A13: Read actual player time for accuracy, not cached currentTime
        let played = player?.currentTime().seconds ?? currentTime
        let threshold = min(240, duration * 0.5)
        if played >= threshold {
            scrobbleSubmitted = true
            lastScrobbleTime = Date()
            PersistenceController.shared.recordPlay(song: song)
            if UserDefaults.standard.bool(forKey: "scrobblingEnabled") {
                Task {
                    try? await AppState.shared.subsonicClient.scrobble(id: song.id, submission: true)
                }
            }
        }
    }
}
