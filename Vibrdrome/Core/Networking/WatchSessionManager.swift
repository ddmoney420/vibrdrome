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
        let context = WatchPlaybackActions.nowPlayingContext(
            title: title, artist: artist, album: album, isPlaying: isPlaying
        )

        try? wcSession?.updateApplicationContext(context)

        if wcSession?.isReachable == true {
            wcSession?.sendMessage(context, replyHandler: nil)
        }
    }

    func sendNowPlayingUpdate(title: String, artist: String, album: String,
                              isPlaying: Bool, coverArtData: Data?) {
        guard isReady else { return }
        var context = WatchPlaybackActions.nowPlayingContext(
            title: title, artist: artist, album: album, isPlaying: isPlaying
        )

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
        wcSession?.sendMessage(
            WatchPlaybackActions.playbackStateContext(isPlaying: isPlaying),
            replyHandler: nil
        )
    }

    /// Re-send current now playing state (e.g. after watch app installs or session activates)
    private func sendCurrentStateIfPlaying() {
        let playback = WatchPlaybackActions.playback
        guard let song = playback.currentSong else { return }
        sendNowPlayingUpdate(
            title: song.title,
            artist: song.displayArtist ?? "Unknown Artist",
            album: song.album ?? "",
            isPlaying: playback.isPlaying
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
        WatchPlaybackActions.handlePlaybackCommand(command, volume: volume)
    }

    @MainActor @discardableResult
    private func handleLibraryCommand(_ command: String) -> Bool {
        switch command {
        case "playFavorites":
            Task { await playStarred(shuffle: false) }
        case "shuffleFavorites":
            Task { await playStarred(shuffle: true) }
        case "shuffleAll":
            Task {
                guard let songs = try? await SubsonicClientProvider.shared.client?.getRandomSongs(size: 50),
                      let first = songs.first else { return }
                WatchPlaybackActions.playback.play(song: first, from: songs, at: 0)
            }
        case let cmd where cmd.hasPrefix("playAlbum:"):
            Task { await playAlbum(id: String(cmd.dropFirst("playAlbum:".count))) }
        case let cmd where cmd.hasPrefix("playPlaylist:"):
            Task { await playPlaylist(id: String(cmd.dropFirst("playPlaylist:".count))) }
        case let cmd where cmd.hasPrefix("skipToIndex:"):
            if let index = Int(cmd.dropFirst("skipToIndex:".count)) {
                WatchPlaybackActions.skipToIndex(relative: index)
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
        WatchPlaybackActions.playback.play(song: list[0], from: list, at: 0)
    }

    private func playAlbum(id: String) async {
        guard let album = try? await SubsonicClientProvider.shared.client?.getAlbum(id: id),
              let songs = album.song, let first = songs.first else { return }
        WatchPlaybackActions.playback.play(song: first, from: songs, at: 0)
    }

    private func playPlaylist(id: String) async {
        guard let playlist = try? await SubsonicClientProvider.shared.client?.getPlaylist(id: id),
              let songs = playlist.entry, let first = songs.first else { return }
        WatchPlaybackActions.playback.play(song: first, from: songs, at: 0)
    }

}

/// Provides access to the current SubsonicClient from watch commands.
@MainActor
final class SubsonicClientProvider {
    static let shared = SubsonicClientProvider()
    weak var client: SubsonicClient?
}
#endif
