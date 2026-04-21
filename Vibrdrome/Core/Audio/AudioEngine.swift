import AVFoundation
import Combine
import Foundation
import MediaPlayer
import Network
import Observation
import SwiftData
import os.log

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
    
    /// Current predownload status from PredownloadManager
    var predownloadStatus: PredownloadStatus = .idle
    
    /// Track last N random songs played to avoid duplicates
    var randomSongsPlayedIds: [String] = []
    static let maxRandomSongsPlayed = 50 // Maximum songs to track for duplicate avoidance
    static let predownloadedCategory = "pre-downloaded"
    static let predownloadedCacheTimeMins = 30.0

    // MARK: - Playback Mode

    /// The currently active playback topology
    var activeMode: PlaybackMode = .gapless

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
    var currentReplayGainFactor: Float = 1.0

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

    // MARK: - Queue

    var queue: [Song] = []
    var currentIndex: Int = 0
    var shuffleEnabled = false
    var repeatMode: RepeatMode = .off
    var shufflePlayCount = 0

    // MARK: - Repeat-One Tracking

    /// Tracks whether repeat-one has already replayed the current track.
    /// When true, the next track-end advances instead of replaying.
    var repeatOneUsed = false

    // MARK: - Artist Radio (methods in AudioEngine+Radio.swift)

    var isRadioMode = false
    var radioSeedArtistName: String?
    /// Context label for what's playing (e.g. "Playlist: Metal Mix"). Nil for normal album playback.
    var playingFromContext: String?
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
    var lookaheadItem: AVPlayerItem?
    var lookaheadSongId: String?
    var lookaheadIndex: Int?

    /// Predownload manager for long-running download operations
    internal let predownloadManager = PredownloadManager()

    /// Observer tokens — accessed by +Observers and +Crossfade extensions
    private var timeObserver: Any?
    private weak var timeObserverPlayer: AVPlayer?
    private var itemEndObserver: Any?
    private var lookaheadEndObserver: Any?
    private var durationObserver: AnyCancellable?
    private var bufferingObserver: AnyCancellable?
    private var statusObserver: AnyCancellable?

    /// Scrobble tracking
    var scrobbleSubmitted = false
    var trackStartTime: Date?
    var lastScrobbleTime: Date?
    var generation: Int = 0

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

    let networkMonitor = NWPathMonitor()
    var isOnCellular = false
    var isNetworkConstrained = false

    var gaplessEnabled: Bool {
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

    /// Auto-suggest guard flag
    var isAutoSuggesting = false

    private init() {
        guard !isUITesting else { return }
        AudioSessionManager.shared.configure()
        startNetworkMonitor()
        // Sync EQ coefficients on launch so taps pick up saved preset
        EQEngine.shared.syncCoefficients()
    }

    // MARK: - Mode Selection

    func selectMode(for song: Song) -> PlaybackMode {
        if crossfadeDuration > 0 { return .crossfade }
        return .gapless
    }

    func tearDownCurrentMode() {
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

    // MARK: - Volume

    var volume: Float {
        get { userVolume }
        set { userVolume = max(0, min(1, newValue)) }
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

    // MARK: - EQ Tap

    /// Whether the visualizer is currently active (keeps audio tap alive for FFT)
    var visualizerActive = false

    /// Apply audio tap to an AVPlayerItem for EQ processing and/or FFT spectrum extraction.
    /// Always applied — the tap is passthrough when EQ gains are zero, and FFT extraction
    /// is lightweight. This avoids audio stutter when opening the visualizer mid-playback.
    func applyEQTapIfNeeded(to item: AVPlayerItem) {
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

    /// Called when user toggles EQ on/off — syncs coefficients (tap stays active always)
    func applyEQToggle(enabled: Bool) {
        eqEnabled = enabled
        if enabled {
            EQEngine.shared.syncCoefficients()
        }
        // Tap is always active — EQ coefficients are zeroed when disabled,
        // so the tap passes through audio unchanged. No need to add/remove.
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
            return smartShuffleNextIndex()
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
        audioLog.debug("aldebug: prepareLookahead called \(self.activeMode == .gapless) \(self.gaplessEnabled)")
        
        guard activeMode == .gapless,
              gaplessEnabled,
              let nextIdx = nextSongIndex() else {
            clearLookahead()
            audioLog.debug("aldebug: prepareLookahead - clearLookahead")
            return
        }

        let nextSong = queue[nextIdx]

        let url = resolveURL(for: nextSong)

        // Check if this URL is already in use by current player items
        if (lookaheadItem != nil) {
           let oldLookaheadAsset = lookaheadItem!.asset as? AVURLAsset
            audioLog.debug("aldebug: old url: \(oldLookaheadAsset?.url.absoluteString ?? "nil")")
            if (oldLookaheadAsset?.url == url) {
                audioLog.debug("aldebug: prepareLookahead - SAME look ahead item url")
                return
            } else {
                audioLog.debug("aldebug: prepareLookahead - CHANGING look ahead item url")
            }
        }

        clearLookahead()

        let item = Self.makePlayerItem(url: url)
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

    // MARK: - Player Item Management

    /// Create an AVPlayerItem with HTTP headers that improve reverse proxy compatibility.
    /// Prevents proxies from gzip-compressing audio streams, which corrupts transcoded audio.
    static func makePlayerItem(url: URL) -> AVPlayerItem {
        audioLog.debug("aldebug: makePlayerItem called \(url)")
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["Accept-Encoding": "identity"],
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        return item
    }

    func replacePlayerItem(with url: URL) {
        audioLog.debug("aldebug: replacePlayerItem called \(url)")
        tearDownObservers()
        clearLookahead()
        generation += 1

        let item = Self.makePlayerItem(url: url)
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
}
