import Foundation
@preconcurrency import WatchConnectivity

// MARK: - Data Models

struct WatchQueueItem: Sendable {
    let title: String
    let artist: String
}

struct WatchAlbumItem: Sendable {
    let id: String
    let name: String
    let artist: String
}

struct WatchPlaylistItem: Sendable {
    let id: String
    let name: String
    let songCount: Int
}

/// Sendable snapshot extracted from WCSession dictionaries.
private struct NowPlayingSnapshot: Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let isPlaying: Bool?
    let coverArtData: Data?
    let elapsed: Double?
    let duration: Double?
    let isStarred: Bool?
    let isShuffleOn: Bool?
    let repeatMode: String?
    let sleepTimerActive: Bool?
    let queue: [[String: String]]?
    let recentAlbums: [[String: String]]?
    let playlists: [[String: String]]?

    init(_ data: [String: Any]) {
        title = data["title"] as? String
        artist = data["artist"] as? String
        album = data["album"] as? String
        isPlaying = data["isPlaying"] as? Bool
        coverArtData = data["coverArtData"] as? Data
        elapsed = data["elapsed"] as? Double
        duration = data["duration"] as? Double
        isStarred = data["isStarred"] as? Bool
        isShuffleOn = data["isShuffleOn"] as? Bool
        repeatMode = data["repeatMode"] as? String
        sleepTimerActive = data["sleepTimerActive"] as? Bool
        queue = data["queue"] as? [[String: String]]
        recentAlbums = data["recentAlbums"] as? [[String: String]]
        playlists = data["playlists"] as? [[String: String]]
    }
}

// MARK: - Session Manager

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    // Now playing
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var isPlaying: Bool = false
    @Published var coverArtData: Data?
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var isStarred: Bool = false
    @Published var isShuffleOn: Bool = false
    @Published var repeatMode: String = "off"
    @Published var sleepTimerActive: Bool = false

    // Queue & library
    @Published var queue: [WatchQueueItem] = []
    @Published var recentAlbums: [WatchAlbumItem] = []
    @Published var playlists: [WatchPlaylistItem] = []

    private var wcSession: WCSession

    override init() {
        wcSession = WCSession.default
        super.init()
        wcSession.delegate = self
        wcSession.activate()
    }

    // MARK: - Commands

    func togglePlayPause() { sendCommand("togglePlayPause") }
    func next() { sendCommand("next") }
    func previous() { sendCommand("previous") }

    func toggleStar() {
        isStarred.toggle()
        sendCommand("toggleStar")
    }

    func toggleShuffle() {
        isShuffleOn.toggle()
        sendCommand("toggleShuffle")
    }

    func cycleRepeat() {
        switch repeatMode {
        case "off": repeatMode = "all"
        case "all": repeatMode = "one"
        default: repeatMode = "off"
        }
        sendCommand("cycleRepeat")
    }

    func setVolume(_ volume: Float) {
        guard wcSession.isReachable else { return }
        wcSession.sendMessage(["command": "setVolume", "volume": volume], replyHandler: nil)
    }

    func sendCommand(_ command: String) {
        guard wcSession.isReachable else { return }
        wcSession.sendMessage(["command": command], replyHandler: nil)
    }

    // MARK: - Apply Updates

    private func applySnapshot(_ snapshot: NowPlayingSnapshot) {
        if let title = snapshot.title { self.title = title }
        if let artist = snapshot.artist { self.artist = artist }
        if let album = snapshot.album { self.album = album }
        if let isPlaying = snapshot.isPlaying { self.isPlaying = isPlaying }
        if let artData = snapshot.coverArtData { self.coverArtData = artData }
        if let elapsed = snapshot.elapsed { self.elapsed = elapsed }
        if let duration = snapshot.duration { self.duration = duration }
        if let isStarred = snapshot.isStarred { self.isStarred = isStarred }
        if let isShuffleOn = snapshot.isShuffleOn { self.isShuffleOn = isShuffleOn }
        if let repeatMode = snapshot.repeatMode { self.repeatMode = repeatMode }
        if let sleepTimerActive = snapshot.sleepTimerActive { self.sleepTimerActive = sleepTimerActive }

        if let queueData = snapshot.queue {
            queue = queueData.map {
                WatchQueueItem(title: $0["title"] ?? "", artist: $0["artist"] ?? "")
            }
        }

        if let albumsData = snapshot.recentAlbums {
            recentAlbums = albumsData.map {
                WatchAlbumItem(id: $0["id"] ?? "", name: $0["name"] ?? "", artist: $0["artist"] ?? "")
            }
        }

        if let playlistsData = snapshot.playlists {
            playlists = playlistsData.map {
                WatchPlaylistItem(
                    id: $0["id"] ?? "",
                    name: $0["name"] ?? "",
                    songCount: Int($0["songCount"] ?? "0") ?? 0
                )
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let snapshot = NowPlayingSnapshot(applicationContext)
        Task { @MainActor in applySnapshot(snapshot) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let snapshot = NowPlayingSnapshot(message)
        Task { @MainActor in applySnapshot(snapshot) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let snapshot = NowPlayingSnapshot(message)
        Task { @MainActor in applySnapshot(snapshot) }
        replyHandler([:])
    }
}
