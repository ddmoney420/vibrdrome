#if os(iOS)
import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    private var wcSession: WCSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        wcSession = session
    }

    private var isReady: Bool {
        guard let session = wcSession,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return false }
        return true
    }

    // MARK: - Send Now Playing

    func sendNowPlayingUpdate(title: String, artist: String, album: String, isPlaying: Bool) {
        guard isReady else { return }
        let engine = AudioEngine.shared

        var context: [String: Any] = [
            "title": title,
            "artist": artist,
            "album": album,
            "isPlaying": isPlaying,
            "elapsed": engine.currentTime,
            "duration": engine.duration,
            "isStarred": engine.currentSong?.starred != nil,
            "isShuffleOn": engine.shuffleEnabled,
            "repeatMode": repeatModeString(engine.repeatMode),
            "sleepTimerActive": SleepTimer.shared.isActive,
        ]

        // Send queue (up next, max 20)
        let upNext = engine.upNext.prefix(20)
        context["queue"] = upNext.map { ["title": $0.title, "artist": $0.artist ?? ""] }

        try? wcSession?.updateApplicationContext(context)

        if wcSession?.isReachable == true {
            wcSession?.sendMessage(context, replyHandler: nil)
        }
    }

    func sendNowPlayingUpdate(title: String, artist: String, album: String,
                              isPlaying: Bool, coverArtData: Data?) {
        guard isReady else { return }
        let engine = AudioEngine.shared

        var context: [String: Any] = [
            "title": title,
            "artist": artist,
            "album": album,
            "isPlaying": isPlaying,
            "elapsed": engine.currentTime,
            "duration": engine.duration,
            "isStarred": engine.currentSong?.starred != nil,
            "isShuffleOn": engine.shuffleEnabled,
            "repeatMode": repeatModeString(engine.repeatMode),
            "sleepTimerActive": SleepTimer.shared.isActive,
        ]

        let upNext = engine.upNext.prefix(20)
        context["queue"] = upNext.map { ["title": $0.title, "artist": $0.artist ?? ""] }

        // Include art in the same message so watch processes everything in one snapshot
        if let artData = coverArtData {
            context["coverArtData"] = artData
        }

        // Context update (without art -- too large for applicationContext)
        var contextWithoutArt = context
        contextWithoutArt.removeValue(forKey: "coverArtData")
        try? wcSession?.updateApplicationContext(contextWithoutArt)

        // Send full message including art
        if wcSession?.isReachable == true {
            wcSession?.sendMessage(context, replyHandler: nil)
        }
    }

    func sendPlaybackStateUpdate(isPlaying: Bool) {
        guard isReady, wcSession?.isReachable == true else { return }
        let engine = AudioEngine.shared
        wcSession?.sendMessage([
            "isPlaying": isPlaying,
            "elapsed": engine.currentTime,
            "sleepTimerActive": SleepTimer.shared.isActive,
        ], replyHandler: nil)
    }

    /// Re-send current now playing state (e.g. after watch app installs or session activates)
    private func sendCurrentStateIfPlaying() {
        let engine = AudioEngine.shared
        guard let song = engine.currentSong else { return }
        sendNowPlayingUpdate(
            title: song.title,
            artist: song.artist ?? "Unknown Artist",
            album: song.album ?? "",
            isPlaying: engine.isPlaying
        )
    }

    /// Send library data (playlists, recent albums) — call periodically or on watch request
    func sendLibraryData(recentAlbums: [[String: String]], playlists: [[String: String]]) {
        guard isReady else { return }
        var context: [String: Any] = [:]
        context["recentAlbums"] = recentAlbums
        context["playlists"] = playlists
        if wcSession?.isReachable == true {
            wcSession?.sendMessage(context, replyHandler: nil)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            Task { @MainActor in sendCurrentStateIfPlaying() }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        if session.isWatchAppInstalled {
            Task { @MainActor in sendCurrentStateIfPlaying() }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = message["command"] as? String else { return }
        let volume = message["volume"] as? Float
        Task { @MainActor in
            handleCommand(command, volume: volume)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let command = message["command"] as? String else {
            replyHandler([:])
            return
        }
        let volume = message["volume"] as? Float
        Task { @MainActor in
            handleCommand(command, volume: volume)
        }
        replyHandler([:])
    }

    @MainActor
    private func handleCommand(_ command: String, volume: Float?) {
        if handlePlaybackCommand(command, volume: volume) { return }
        if handleLibraryCommand(command) { return }
        handleTimerCommand(command)
    }

    @MainActor @discardableResult
    private func handlePlaybackCommand(_ command: String, volume: Float?) -> Bool {
        let engine = AudioEngine.shared
        switch command {
        case "togglePlayPause": engine.togglePlayPause()
        case "next": engine.next()
        case "previous": engine.previous()
        case "setVolume": if let volume { engine.volume = volume }
        case "toggleStar":
            guard let song = engine.currentSong else { return true }
            Task {
                if song.starred != nil {
                    try? await OfflineActionQueue.shared.unstar(id: song.id)
                } else {
                    try? await OfflineActionQueue.shared.star(id: song.id)
                }
            }
        case "toggleShuffle": engine.toggleShuffle()
        case "cycleRepeat": engine.cycleRepeatMode()
        case "startRadio":
            if let song = engine.currentSong { engine.startRadioFromSong(song) }
        default: return false
        }
        return true
    }

    @MainActor @discardableResult
    private func handleLibraryCommand(_ command: String) -> Bool {
        let engine = AudioEngine.shared
        switch command {
        case "playFavorites":
            Task { await playStarred(shuffle: false) }
        case "shuffleFavorites":
            Task { await playStarred(shuffle: true) }
        case "shuffleAll":
            Task {
                guard let songs = try? await SubsonicClientProvider.shared.client?.getRandomSongs(size: 50),
                      let first = songs.first else { return }
                engine.play(song: first, from: songs, at: 0)
            }
        case let cmd where cmd.hasPrefix("playAlbum:"):
            Task { await playAlbum(id: String(cmd.dropFirst("playAlbum:".count))) }
        case let cmd where cmd.hasPrefix("playPlaylist:"):
            Task { await playPlaylist(id: String(cmd.dropFirst("playPlaylist:".count))) }
        case let cmd where cmd.hasPrefix("skipToIndex:"):
            if let index = Int(cmd.dropFirst("skipToIndex:".count)) {
                let abs = engine.currentIndex + 1 + index
                guard abs < engine.queue.count else { return true }
                engine.play(song: engine.queue[abs], from: engine.queue, at: abs)
            }
        default: return false
        }
        return true
    }
    @MainActor
    private func handleTimerCommand(_ command: String) {
        switch command {
        case "sleepTimer15": SleepTimer.shared.start(mode: .minutes(15))
        case "sleepTimer30": SleepTimer.shared.start(mode: .minutes(30))
        case "sleepTimer45": SleepTimer.shared.start(mode: .minutes(45))
        case "sleepTimer60": SleepTimer.shared.start(mode: .minutes(60))
        case "sleepTimerEndOfTrack": SleepTimer.shared.start(mode: .endOfTrack)
        case "sleepTimerCancel": SleepTimer.shared.stop()
        default: break
        }
    }

    private func playStarred(shuffle: Bool) async {
        guard let starred = try? await SubsonicClientProvider.shared.client?.getStarred(),
              let songs = starred.song, !songs.isEmpty else { return }
        let list = shuffle ? songs.shuffled() : songs
        AudioEngine.shared.play(song: list[0], from: list, at: 0)
    }

    private func playAlbum(id: String) async {
        guard let album = try? await SubsonicClientProvider.shared.client?.getAlbum(id: id),
              let songs = album.song, let first = songs.first else { return }
        AudioEngine.shared.play(song: first, from: songs, at: 0)
    }

    private func playPlaylist(id: String) async {
        guard let playlist = try? await SubsonicClientProvider.shared.client?.getPlaylist(id: id),
              let songs = playlist.entry, let first = songs.first else { return }
        AudioEngine.shared.play(song: first, from: songs, at: 0)
    }

    private func repeatModeString(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: "off"
        case .all: "all"
        case .one: "one"
        }
    }
}

/// Provides access to the current SubsonicClient from watch commands.
@MainActor
final class SubsonicClientProvider {
    static let shared = SubsonicClientProvider()
    weak var client: SubsonicClient?
}
#endif
