import AVFoundation
import Combine
import Foundation
import MediaPlayer
import Network
import Observation
import SwiftData
import os.log

private let audioLog = Logger(subsystem: "com.veydrune.app", category: "Audio")

enum RepeatMode: Sendable {
    case off, all, one
}

/// Active playback topology — mutually exclusive
enum PlaybackMode: Sendable {
    /// AVQueuePlayer with gapless lookahead (default)
    case gapless
    /// Dual AVPlayer with volume ramp crossfade
    case crossfade
    /// AVAudioEngine pipeline with 10-band EQ (local files only)
    case eq
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

    // MARK: - Playback Mode

    /// The currently active playback topology
    private(set) var activeMode: PlaybackMode = .gapless

    /// Whether EQ processing is enabled (user setting)
    var eqEnabled: Bool {
        UserDefaults.standard.bool(forKey: "eqEnabled")
    }

    /// Whether crossfade is currently ramping between tracks
    var isCrossfading = false

    // MARK: - Playback Speed & Volume

    /// Current playback rate (0.5x to 2.0x)
    var playbackRate: Float = 1.0 {
        didSet {
            switch activeMode {
            case .gapless:
                if isPlaying { gaplessPlayer?.rate = playbackRate }
            case .crossfade:
                if isPlaying {
                    crossfadeController.activePlayer?.rate = playbackRate
                    if isCrossfading {
                        crossfadeController.inactivePlayer?.rate = playbackRate
                    }
                }
            case .eq:
                EQEngine.shared.setRate(playbackRate)
            }
            NowPlayingManager.shared.updatePlaybackRate(playbackRate)
        }
    }

    /// User volume slider value (0.0-1.0)
    var userVolume: Float = 1.0 { didSet { applyEffectiveVolume() } }

    /// Per-track ReplayGain factor (computed from song metadata)
    private(set) var currentReplayGainFactor: Float = 1.0

    func setReplayGainFactor(_ factor: Float) { currentReplayGainFactor = factor }

    /// ReplayGain mode setting
    enum ReplayGainMode: String, Sendable {
        case off, track, album
    }

    var replayGainMode: ReplayGainMode {
        ReplayGainMode(
            rawValue: UserDefaults.standard.string(forKey: "replayGainMode") ?? "off"
        ) ?? .off
    }

    /// Compute and apply the effective volume from all factors
    func applyEffectiveVolume() {
        let sleepFade = SleepTimer.shared.fadeFactor
        let base = userVolume * currentReplayGainFactor * sleepFade

        switch activeMode {
        case .gapless:
            gaplessPlayer?.volume = max(0, min(1, base))
        case .crossfade:
            let cc = crossfadeController
            cc.activePlayer?.volume = max(0, min(1, base * cc.outFactor))
            cc.inactivePlayer?.volume = max(0, min(1, base * cc.inFactor))
        case .eq:
            EQEngine.shared.setVolume(max(0, min(1, base)))
        }
    }

    /// Compute ReplayGain factor for a song
    func computeReplayGainFactor(for song: Song) -> Float {
        guard let rg = song.replayGain else { return 1.0 }
        let gain: Double?
        switch replayGainMode {
        case .off: return 1.0
        case .track: gain = rg.trackGain
        case .album: gain = rg.albumGain ?? rg.trackGain
        }
        guard let gainDb = gain else { return 1.0 }
        let linear = Float(pow(10, gainDb / 20))
        return max(0.0, min(2.0, linear))
    }

    // MARK: - Queue

    var queue: [Song] = []
    var currentIndex: Int = 0
    var shuffleEnabled = false
    var repeatMode: RepeatMode = .off
    private var shufflePlayCount = 0

    // MARK: - Artist Radio (methods in AudioEngine+Radio.swift)

    var isRadioMode = false
    var radioSeedArtistName: String?
    private var radioSkippedIds: Set<String> = []
    private var radioRefillTask: Task<Void, Never>?

    // Radio state accessors for extension
    func clearRadioSkippedIds() { radioSkippedIds.removeAll() }
    func insertRadioSkippedId(_ id: String) { radioSkippedIds.insert(id) }
    func getRadioSkippedIds() -> Set<String> { radioSkippedIds }
    var hasActiveRadioRefillTask: Bool {
        radioRefillTask != nil && radioRefillTask?.isCancelled != true
    }
    func setRadioRefillTask(_ task: Task<Void, Never>) { radioRefillTask = task }
    func cancelRadioRefillTask() { radioRefillTask?.cancel(); radioRefillTask = nil }

    // MARK: - Player Internals (accessed by extensions)

    /// AVQueuePlayer for gapless mode
    private(set) var gaplessPlayer: AVQueuePlayer?

    /// Lookahead state for gapless mode
    private var lookaheadItem: AVPlayerItem?
    private var lookaheadSongId: String?
    private var lookaheadIndex: Int?

    /// Observer tokens — accessed by +Observers and +Crossfade extensions
    private var timeObserver: Any?
    private weak var timeObserverPlayer: AVPlayer?
    private var itemEndObserver: Any?
    private var lookaheadEndObserver: Any?
    private var durationObserver: AnyCancellable?
    private var bufferingObserver: AnyCancellable?
    private var statusObserver: AnyCancellable?
    private var eqSyncTimer: Timer?

    /// Scrobble tracking
    private(set) var scrobbleSubmitted = false
    private var trackStartTime: Date?
    private(set) var lastScrobbleTime: Date?
    private(set) var generation: Int = 0

    func incrementGeneration() { generation += 1 }
    var generationValue: Int { generation }
    var isScrobbleSubmitted: Bool { scrobbleSubmitted }
    func resetScrobbleState() { scrobbleSubmitted = false; trackStartTime = Date() }
    func markScrobbleSubmitted() { scrobbleSubmitted = true; lastScrobbleTime = Date() }
    var hasLookahead: Bool { lookaheadItem != nil }

    // Observer accessor methods for extensions
    func removeCurrentTimeObserver() {
        if let timeObserver {
            timeObserverPlayer?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
            self.timeObserverPlayer = nil
        }
    }

    func setTimeObserver(observer: Any?) { timeObserver = observer }
    func setTimeObserver(player: AVPlayer?) { timeObserverPlayer = player }
    func setItemEndObserver(_ observer: Any?) { itemEndObserver = observer }
    func removeItemEndObserver() {
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
    }

    func removeLookaheadEndObserver() {
        if let lookaheadEndObserver {
            NotificationCenter.default.removeObserver(lookaheadEndObserver)
            self.lookaheadEndObserver = nil
        }
    }

    func setLookaheadEndObserver(_ observer: Any?) { lookaheadEndObserver = observer }
    func setDurationObserver(_ sub: AnyCancellable?) { durationObserver = sub }
    func setBufferingObserver(_ sub: AnyCancellable?) { bufferingObserver = sub }
    func setStatusObserver(_ sub: AnyCancellable?) { statusObserver = sub }

    func clearPropertyObservers() {
        durationObserver?.cancel(); durationObserver = nil
        bufferingObserver?.cancel(); bufferingObserver = nil
        statusObserver?.cancel(); statusObserver = nil
    }

    func invalidateEQSyncTimer() {
        eqSyncTimer?.invalidate(); eqSyncTimer = nil
    }

    func setEQSyncTimer(_ timer: Timer) { eqSyncTimer = timer }

    private let networkMonitor = NWPathMonitor()
    private var isOnCellular = false

    private var gaplessEnabled: Bool {
        UserDefaults.standard.bool(forKey: "gaplessPlayback")
    }

    /// Crossfade duration in seconds (0 = disabled)
    var crossfadeDuration: Int {
        UserDefaults.standard.integer(forKey: "crossfadeDuration")
    }

    /// Crossfade controller for dual-player transitions
    let crossfadeController = CrossfadeController()

    /// Whether the current track is a local (downloaded) file
    var isCurrentTrackLocal: Bool {
        guard let song = currentSong else { return false }
        return isTrackLocal(song)
    }

    /// The active AVPlayer for the current mode (gapless or crossfade)
    var activePlayer: AVPlayer? {
        switch activeMode {
        case .gapless: return gaplessPlayer
        case .crossfade: return crossfadeController.activePlayer
        case .eq: return nil
        }
    }

    private init() {
        AudioSessionManager.shared.configure()
        startNetworkMonitor()
        setupEQCompletionHandler()
    }

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnCellular = path.usesInterfaceType(.cellular)
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "com.veydrune.network"))
    }

    private func setupEQCompletionHandler() {
        EQEngine.shared.onTrackEnd = { [weak self] in
            Task { @MainActor in
                self?.handleTrackEnd()
            }
        }
    }

    private var currentMaxBitRate: Int? {
        let defaults = UserDefaults.standard
        let key = isOnCellular ? "cellularMaxBitRate" : "wifiMaxBitRate"
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }

    // MARK: - Mode Selection

    private func selectMode(for song: Song) -> PlaybackMode {
        if eqEnabled && isTrackLocal(song) { return .eq }
        if crossfadeDuration > 0 { return .crossfade }
        return .gapless
    }

    private func tearDownCurrentMode() {
        switch activeMode {
        case .gapless:
            tearDownObservers()
            clearLookahead()
            gaplessPlayer?.pause()
            gaplessPlayer?.removeAllItems()
        case .crossfade:
            crossfadeController.tearDown()
            tearDownObservers()
            gaplessPlayer?.pause()
            gaplessPlayer?.removeAllItems()
        case .eq:
            EQEngine.shared.stop()
            tearDownObservers()
            gaplessPlayer?.pause()
            gaplessPlayer?.removeAllItems()
        }
    }

    // MARK: - Playback Control

    func play(song: Song, from newQueue: [Song]? = nil, at index: Int = 0) {
        submitScrobbleIfNeeded()

        if isCrossfading {
            crossfadeController.forceComplete()
            isCrossfading = false
        }

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

        currentSong = song
        currentRadioStation = nil
        scrobbleSubmitted = false
        trackStartTime = Date()
        currentTime = 0
        duration = 0

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
        case .eq:
            startEQPlayback(url: url)
            applyEffectiveVolume()
        }

        isPlaying = true
        NowPlayingManager.shared.update(song: song, isPlaying: true)
        scrobbleNowPlaying(songId: song.id)
    }

    func playRadio(station: InternetRadioStation) {
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func pause() {
        switch activeMode {
        case .gapless, .crossfade:
            activePlayer?.pause()
        case .eq:
            EQEngine.shared.pause()
        }
        isPlaying = false
        NowPlayingManager.shared.updatePlaybackState(isPlaying: false, elapsed: currentTime)
    }

    func resume() {
        switch activeMode {
        case .gapless:
            if let song = currentSong, gaplessPlayer?.currentItem == nil {
                let savedTime = currentTime
                let url = resolveURL(for: song)
                replacePlayerItem(with: url)
                if savedTime > 0 { seek(to: savedTime) }
                prepareLookahead()
            }
            gaplessPlayer?.rate = playbackRate
        case .crossfade:
            if let song = currentSong,
               crossfadeController.activePlayer?.currentItem == nil {
                let savedTime = currentTime
                let url = resolveURL(for: song)
                crossfadeController.loadOnActive(url: url)
                if savedTime > 0 {
                    let cmTime = CMTime(seconds: savedTime, preferredTimescale: 1000)
                    crossfadeController.activePlayer?.seek(to: cmTime)
                }
            }
            crossfadeController.activePlayer?.rate = playbackRate
        case .eq:
            EQEngine.shared.resume()
        }
        isPlaying = true
        NowPlayingManager.shared.updatePlaybackState(isPlaying: true, elapsed: currentTime)
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func next() {
        guard !queue.isEmpty else { return }
        submitScrobbleIfNeeded()

        if isCrossfading {
            crossfadeController.forceComplete()
            isCrossfading = false
        }

        if repeatMode == .one {
            restartCurrentTrack()
            return
        }

        guard advanceIndex() else { return }
        play(song: queue[currentIndex])
        refillRadioIfNeeded()
    }

    private func restartCurrentTrack() {
        trackStartTime = Date()
        switch activeMode {
        case .gapless, .crossfade:
            seekInternal(to: 0) { [weak self] in
                self?.scrobbleSubmitted = false
                self?.activePlayer?.play()
            }
        case .eq:
            EQEngine.shared.seek(to: 0)
            EQEngine.shared.resume()
            scrobbleSubmitted = false
        }
    }

    private func advanceIndex() -> Bool {
        if shuffleEnabled { return advanceShuffleIndex() }
        currentIndex += 1
        if currentIndex >= queue.count {
            if repeatMode == .all {
                currentIndex = 0
            } else if isRadioMode {
                currentIndex = queue.count - 1
                refillRadioIfNeeded()
                return false
            } else {
                currentIndex = queue.count - 1
                pause()
                return false
            }
        }
        return true
    }

    private func advanceShuffleIndex() -> Bool {
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
        var newIndex = Int.random(in: 0..<(queue.count - 1))
        if newIndex >= currentIndex { newIndex += 1 }
        currentIndex = newIndex
        return true
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
        guard duration > 0 || time == 0 else { return }
        let clampedTime = max(0, min(time, duration > 0 ? duration : 0))

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

        switch activeMode {
        case .gapless, .crossfade:
            guard activePlayer != nil else { return }
            isSeeking = true
            let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 1000)
            activePlayer?.seek(
                to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.currentTime = clampedTime
                    NowPlayingManager.shared.updateElapsedTime(clampedTime)
                    self.isSeeking = false
                }
            }
        case .eq:
            EQEngine.shared.seek(to: clampedTime)
            currentTime = clampedTime
            NowPlayingManager.shared.updateElapsedTime(clampedTime)
        }
    }

    func stop() {
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Volume

    var volume: Float {
        get { userVolume }
        set { userVolume = max(0, min(1, newValue)) }
    }

    // MARK: - Shuffle / Repeat

    func toggleShuffle() {
        shuffleEnabled.toggle()
        shufflePlayCount = 0
        if activeMode == .gapless { prepareLookahead() }
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        if activeMode == .gapless { prepareLookahead() }
    }

    // MARK: - Queue Management

    var upNext: [Song] {
        guard !queue.isEmpty, currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    func addToQueue(_ song: Song) {
        queue.append(song)
        if queue.count == currentIndex + 2 && activeMode == .gapless {
            prepareLookahead()
        }
    }

    func addToQueueNext(_ song: Song) {
        queue.insert(song, at: min(currentIndex + 1, queue.count))
        if activeMode == .gapless { prepareLookahead() }
    }

    func removeFromQueue(at index: Int) {
        let absoluteIndex = currentIndex + 1 + index
        guard absoluteIndex > currentIndex, absoluteIndex < queue.count else { return }
        queue.remove(at: absoluteIndex)
        if index == 0 && activeMode == .gapless { prepareLookahead() }
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard currentIndex + 1 < queue.count else { return }
        var upNextSlice = Array(queue[(currentIndex + 1)...])
        upNextSlice.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange((currentIndex + 1)..., with: upNextSlice)
        if activeMode == .gapless { prepareLookahead() }
    }

    func clearQueue() {
        let current = currentIndex < queue.count ? queue[currentIndex] : nil
        queue.removeAll()
        if activeMode == .gapless { clearLookahead() }
        stopRadioMode()
        if let current {
            queue.append(current)
            currentIndex = 0
        } else {
            stop()
        }
    }

    // MARK: - EQ Playback

    func startEQPlayback(url: URL) {
        tearDownObservers()
        clearLookahead()
        generation += 1

        gaplessPlayer?.pause()
        gaplessPlayer?.removeAllItems()

        do {
            try EQEngine.shared.play(url: url, rate: playbackRate)
            duration = EQEngine.shared.fileDuration
            setupEQTimeSync()
        } catch {
            audioLog.error("EQ playback failed, falling back to gapless: \(error)")
            activeMode = .gapless
            replacePlayerItem(with: url)
            applyEffectiveVolume()
            gaplessPlayer?.rate = playbackRate
            prepareLookahead()
        }
    }

    func setupEQTimeSync() {
        removeCurrentTimeObserver()

        let observerGeneration = generation
        invalidateEQSyncTimer()
        eqSyncTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.generation == observerGeneration,
                      self.activeMode == .eq,
                      !self.isSeeking else { return }
                self.currentTime = EQEngine.shared.currentTime
                self.duration = EQEngine.shared.fileDuration
                if self.currentSong != nil {
                    NowPlayingManager.shared.updateElapsedTime(self.currentTime)
                }
                self.autoScrobbleIfNeeded()
            }
        }
    }

    // MARK: - Gapless Lookahead

    func nextSongIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        if repeatMode == .one { return nil }
        if currentRadioStation != nil { return nil }

        if shuffleEnabled {
            guard queue.count > 1 else {
                return repeatMode == .all ? currentIndex : nil
            }
            var candidate = Int.random(in: 0..<(queue.count - 1))
            if candidate >= currentIndex { candidate += 1 }
            return candidate
        } else {
            let next = currentIndex + 1
            if next < queue.count {
                return next
            } else if repeatMode == .all {
                return 0
            } else {
                return nil
            }
        }
    }

    func prepareLookahead() {
        guard activeMode == .gapless,
              gaplessEnabled,
              let nextIdx = nextSongIndex() else {
            clearLookahead()
            return
        }

        let nextSong = queue[nextIdx]
        if lookaheadSongId == nextSong.id { return }

        clearLookahead()

        let url = resolveURL(for: nextSong)
        let item = AVPlayerItem(url: url)
        lookaheadItem = item
        lookaheadSongId = nextSong.id
        lookaheadIndex = nextIdx

        if let gaplessPlayer,
           gaplessPlayer.canInsert(item, after: gaplessPlayer.items().last) {
            gaplessPlayer.insert(item, after: gaplessPlayer.items().last)
        }

        setupLookaheadEndObserver(for: item)
    }

    func clearLookahead() {
        if let lookaheadItem, let gaplessPlayer {
            if gaplessPlayer.items().contains(lookaheadItem)
                && gaplessPlayer.currentItem !== lookaheadItem {
                gaplessPlayer.remove(lookaheadItem)
            }
        }
        removeLookaheadEndObserver()
        lookaheadItem = nil
        lookaheadSongId = nil
        lookaheadIndex = nil
    }

    func handleAutoAdvance() {
        submitScrobbleIfNeeded()

        guard let nextIndex = lookaheadIndex, nextIndex < queue.count else {
            audioLog.warning("Auto-advance but no valid lookahead index")
            return
        }

        currentIndex = nextIndex
        let nextSong = queue[currentIndex]
        currentSong = nextSong
        scrobbleSubmitted = false
        trackStartTime = Date()
        currentTime = 0
        duration = 0

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
        audioLog.info("Gapless auto-advance to: \(nextSong.title) (index \(nextIndex))")
    }

    // MARK: - Private Helpers

    func resolveURL(for song: Song) -> URL {
        let modelContext = PersistenceController.shared.container.mainContext
        let songId = song.id
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
        )
        if let download = try? modelContext.fetch(descriptor).first {
            let fileURL = DownloadManager.absoluteURL(for: download.localFilePath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                CacheManager.shared.touchAccess(songId: songId)
                return fileURL
            }
            modelContext.delete(download)
            do {
                try modelContext.save()
            } catch {
                audioLog.error(
                    "Failed to save after cleaning stale download: \(error)"
                )
            }
        }
        return AppState.shared.subsonicClient.streamURL(
            id: song.id, maxBitRate: currentMaxBitRate
        )
    }

    private func isTrackLocal(_ song: Song) -> Bool {
        let modelContext = PersistenceController.shared.container.mainContext
        let songId = song.id
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
        )
        guard let download = try? modelContext.fetch(descriptor).first else { return false }
        let fileURL = DownloadManager.absoluteURL(for: download.localFilePath)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func seekInternal(
        to time: TimeInterval, completion: (() -> Void)? = nil
    ) {
        switch activeMode {
        case .gapless, .crossfade:
            guard activePlayer != nil else { completion?(); return }
            isSeeking = true
            let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
            nonisolated(unsafe) let safeCompletion = completion
            activePlayer?.seek(
                to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.currentTime = time
                    NowPlayingManager.shared.updateElapsedTime(time)
                    self.isSeeking = false
                    safeCompletion?()
                }
            }
        case .eq:
            EQEngine.shared.seek(to: time)
            currentTime = time
            NowPlayingManager.shared.updateElapsedTime(time)
            completion?()
        }
    }

    func replacePlayerItem(with url: URL) {
        tearDownObservers()
        clearLookahead()
        generation += 1

        let item = AVPlayerItem(url: url)

        if gaplessPlayer == nil {
            gaplessPlayer = AVQueuePlayer(items: [item])
            gaplessPlayer?.automaticallyWaitsToMinimizeStalling = true
        } else {
            gaplessPlayer?.removeAllItems()
            gaplessPlayer?.insert(item, after: nil)
        }

        setupObservers(for: item)
    }

    func handleTrackEnd() {
        SleepTimer.shared.trackDidEnd()
        if !isPlaying { return }

        if repeatMode == .one {
            trackStartTime = Date()
            switch activeMode {
            case .gapless, .crossfade:
                seekInternal(to: 0) { [weak self] in
                    guard let self else { return }
                    if let lastScrobble = self.lastScrobbleTime,
                       Date().timeIntervalSince(lastScrobble) < max(self.duration, 30) {
                        // suppress re-scrobble
                    } else {
                        self.scrobbleSubmitted = false
                    }
                    self.activePlayer?.rate = self.playbackRate
                }
            case .eq:
                EQEngine.shared.seek(to: 0)
                EQEngine.shared.resume()
                if let lastScrobble = lastScrobbleTime,
                   Date().timeIntervalSince(lastScrobble) < max(duration, 30) {
                    // suppress re-scrobble
                } else {
                    scrobbleSubmitted = false
                }
            }
        } else {
            next()
        }
    }
}
