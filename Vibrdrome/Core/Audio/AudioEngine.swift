import AVFoundation
import Combine
import Foundation
import MediaPlayer
import Network
import Observation
import SwiftData
import os.log
#if os(macOS)
import AppKit
#endif
// swiftlint:disable file_length type_body_length

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

private let audioLog = Logger(subsystem: "com.vibrdrome.app", category: "Audio")

enum RepeatMode: Sendable {
    case off, all, one
}

/// Active playback topology — mutually exclusive
enum PlaybackMode: Sendable {
    /// AVQueuePlayer with gapless lookahead (default)
    case gapless
    /// Dual AVPlayer with volume ramp crossfade
    case crossfade
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

    /// Whether EQ processing is enabled (user setting, stored for @Observable reactivity)
    var eqEnabled: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.eqEnabled)

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
            rawValue: UserDefaults.standard.string(forKey: UserDefaultsKeys.replayGainMode) ?? "off"
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
        // Cap at 1.5x (+3.5dB) to prevent clipping on hot masters
        return max(0.0, min(1.5, linear))
    }

    // MARK: - Queue

    var queue: [Song] = []
    var currentIndex: Int = 0
    var shuffleEnabled = false
    var repeatMode: RepeatMode = .off
    private var shufflePlayCount = 0

    // MARK: - Repeat-One Tracking

    /// Tracks whether repeat-one has already replayed the current track.
    /// When true, the next track-end advances instead of replaying.
    private var repeatOneUsed = false

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

    private let networkMonitor = NWPathMonitor()
    private var isOnCellular = false

    private var gaplessEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.gaplessPlayback)
    }

    /// Crossfade duration in seconds (0 = disabled)
    var crossfadeDuration: Int {
        UserDefaults.standard.integer(forKey: UserDefaultsKeys.crossfadeDuration)
    }

    /// Crossfade controller for dual-player transitions
    let crossfadeController = CrossfadeController()

    /// The active AVPlayer for the current mode (gapless or crossfade)
    var activePlayer: AVPlayer? {
        switch activeMode {
        case .gapless: return gaplessPlayer
        case .crossfade: return crossfadeController.activePlayer
        }
    }

    /// When true, skip all AVPlayer/AVAudioSession operations but still update
    /// observable state so the UI renders correctly for XCUITest.
    let isUITesting: Bool = ProcessInfo.processInfo.arguments.contains("--uitesting")

    private init() {
        guard !isUITesting else { return }
        AudioSessionManager.shared.configure()
        startNetworkMonitor()
        // Sync EQ coefficients on launch so taps pick up saved preset
        EQEngine.shared.syncCoefficients()
    }

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnCellular = path.usesInterfaceType(.cellular)
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "com.vibrdrome.network"))
    }

    private var currentMaxBitRate: Int? {
        let defaults = UserDefaults.standard
        let key = isOnCellular ? UserDefaultsKeys.cellularMaxBitRate : UserDefaultsKeys.wifiMaxBitRate
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }

    // MARK: - Mode Selection

    private func selectMode(for song: Song) -> PlaybackMode {
        if crossfadeDuration > 0 { return .crossfade }
        return .gapless
    }

    private func tearDownCurrentMode() {
        // Invalidate any in-flight async EQ Tasks before destroying items
        incrementGeneration()
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
        }
    }

    // MARK: - Playback Control

    // swiftlint:disable:next function_body_length
    func play(song: Song, from newQueue: [Song]? = nil, at index: Int = 0) {
        // UI testing: update observable state only, skip AVPlayer operations
        if isUITesting {
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
            return
        }

        submitScrobbleIfNeeded()

        if isCrossfading {
            incrementGeneration()
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

        let isNewTrack = currentSong?.id != song.id
        currentSong = song
        currentRadioStation = nil
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

        // Load radio station artwork for lock screen
        if let artId = station.radioCoverArtId {
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
                // Use NowPlayingManager's pattern to avoid @MainActor isolation
                // on the MPMediaItemArtwork closure (called on background queue)
                let artwork = makeRadioArtwork(from: image)
                var nowInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                nowInfo[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowInfo
            }
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
            audioLog.error("Failed to reactivate audio session: \(error)")
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
        case .crossfade:
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
            incrementGeneration()
            crossfadeController.forceComplete()
            isCrossfading = false
        }

        // Manual next always advances — reset repeat-one state
        repeatOneUsed = false
        guard advanceIndex() else { return }
        play(song: queue[currentIndex])
        refillRadioIfNeeded()
    }

    private func restartCurrentTrack() {
        trackStartTime = Date()
        seekInternal(to: 0) { [weak self] in
            self?.scrobbleSubmitted = false
            self?.activePlayer?.play()
        }
    }

    private func advanceIndex() -> Bool {
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
        repeatOneUsed = false
        if activeMode == .gapless { prepareLookahead() }
    }

    // MARK: - Queue Management

    var upNext: [Song] {
        guard !queue.isEmpty, currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
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
    private var isAutoSuggesting = false
    private func autoSuggestMore() {
        guard !isAutoSuggesting else { return }
        guard let lastSong = queue.last else {
            pause()
            return
        }
        isAutoSuggesting = true
        Task { @MainActor in
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
            self.isAutoSuggesting = false
        }
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

    // MARK: - EQ Tap

    /// Whether the visualizer is currently active (keeps audio tap alive for FFT)
    var visualizerActive = false

    /// Apply audio tap to an AVPlayerItem for EQ processing and/or FFT spectrum extraction.
    func applyEQTapIfNeeded(to item: AVPlayerItem) {
        guard eqEnabled || visualizerActive else { return }
        let gen = generation
        Task {
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                guard self.generation == gen, let track = tracks.first else { return }
                if let mix = EQTapProcessor.createAudioMix(track: track) {
                    item.audioMix = mix
                }
            } catch {
                audioLog.error("Failed to apply EQ tap: \(error)")
            }
        }
    }

    /// Called when user toggles EQ on/off — applies or removes tap on currently playing item(s)
    func applyEQToggle(enabled: Bool) {
        eqEnabled = enabled
        if enabled {
            // Apply tap to all currently active items
            EQEngine.shared.syncCoefficients()
            switch activeMode {
            case .gapless:
                if let item = gaplessPlayer?.currentItem {
                    applyEQTapForced(to: item)
                }
                if let lookahead = gaplessPlayer?.items().last,
                   lookahead !== gaplessPlayer?.currentItem {
                    applyEQTapForced(to: lookahead)
                }
            case .crossfade:
                if let item = crossfadeController.activePlayer?.currentItem {
                    applyEQTapForced(to: item)
                }
                if isCrossfading, let item = crossfadeController.inactivePlayer?.currentItem {
                    applyEQTapForced(to: item)
                }
            }
        } else {
            // Remove EQ taps from all active items
            switch activeMode {
            case .gapless:
                for item in gaplessPlayer?.items() ?? [] {
                    item.audioMix = nil
                }
            case .crossfade:
                crossfadeController.activePlayer?.currentItem?.audioMix = nil
                crossfadeController.inactivePlayer?.currentItem?.audioMix = nil
            }
        }
    }

    /// Apply EQ tap unconditionally (bypasses eqEnabled check — used by applyEQToggle)
    private func applyEQTapForced(to item: AVPlayerItem) {
        let gen = generation
        Task {
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                guard self.generation == gen, let track = tracks.first else { return }
                if let mix = EQTapProcessor.createAudioMix(track: track) {
                    item.audioMix = mix
                }
            } catch {
                audioLog.error("Failed to apply EQ tap: \(error)")
            }
        }
    }

    // MARK: - Gapless Lookahead

    func nextSongIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        if repeatMode == .all { return currentIndex }  // Gapless loop of same track
        if repeatMode == .one { return nil }  // Handled in handleTrackEnd
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

        applyEQTapIfNeeded(to: item)

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

    func replacePlayerItem(with url: URL) {
        tearDownObservers()
        clearLookahead()
        generation += 1

        let item = AVPlayerItem(url: url)
        applyEQTapIfNeeded(to: item)

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

        switch repeatMode {
        case .all:
            // Loop current track — reload since AVQueuePlayer removed the item
            guard let song = currentSong else { return }
            play(song: song)
        case .one:
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
        case .off:
            next()
        }
    }
}

// swiftlint:enable type_body_length
