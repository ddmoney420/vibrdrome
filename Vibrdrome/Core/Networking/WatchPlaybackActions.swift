#if os(iOS)
import Foundation

/// The playback side of the Watch protocol, separated from WatchConnectivity plumbing.
///
/// **Why this exists.** `WCSession` messages cannot be synthesised reliably without a paired Watch,
/// and `WatchSessionManager`'s initialiser activates a real session. Routing every watch command
/// through named methods here means a test can drive the exact code an incoming message runs
/// without a Watch, a session, or real audio.
///
/// `WatchSessionManager` remains the `WCSessionDelegate` and the message receiver — this type owns
/// no session, no delegate registration and no state. It is an `enum` of static members so nothing
/// retains the manager and no second playback authority can exist.
///
/// Same seam shape as `RemoteCommandManager` and `CarPlayPlaybackActions`, deliberately: one
/// pattern for "external command → named method → façade", not three.
@MainActor
enum WatchPlaybackActions {

    #if DEBUG
    /// Test seam. The real transport members would start AVQueuePlayer, which cannot happen while
    /// the gapless real-time suites are running. Tests substitute a recorder and reset it in
    /// teardown. Production never sets this, and it does not exist in release builds.
    static var playbackOverride: (any ApplicationPlaybackControlling)?
    #endif

    /// Resolved per call, never stored — every watch reply and context must report live state.
    static var playback: any ApplicationPlaybackControlling {
        #if DEBUG
        playbackOverride ?? ApplicationPlayback.shared
        #else
        ApplicationPlayback.shared
        #endif
    }

    // MARK: - Playback commands

    /// Transport, volume, star, shuffle, repeat and radio. Returns `true` when `command` was one of
    /// them, matching the original dispatch contract exactly — including returning `true` for
    /// `toggleStar` with no current song, which is a handled no-op rather than an unknown command.
    ///
    /// Note the Watch protocol has **no `play`, `pause` or `seek`** command: transport is
    /// `togglePlayPause` only, and the sole numeric payload is `setVolume`'s `volume`.
    @discardableResult
    static func handlePlaybackCommand(_ command: String, volume: Float?) -> Bool {
        let playback = playback
        switch command {
        case "togglePlayPause": playback.togglePlayPause()
        case "next": playback.next()
        case "previous": playback.previous()
        // A missing or non-Float `volume` leaves the level untouched, as before. Range clamping is
        // the engine's (`volume` clamps to 0...1); none is added here.
        case "setVolume": if let volume { playback.volume = volume }
        case "toggleStar":
            guard let song = playback.currentSong else { return true }
            Task {
                if song.starred != nil {
                    try? await OfflineActionQueue.shared.unstar(id: song.id)
                } else {
                    try? await OfflineActionQueue.shared.star(id: song.id)
                }
            }
        case "toggleShuffle": playback.toggleShuffle()
        case "cycleRepeat": playback.cycleRepeatMode()
        case "startRadio":
            if let song = playback.currentSong { playback.startRadioFromSong(song) }
        default: return false
        }
        return true
    }

    // MARK: - Queue selection

    /// Absolute queue index for the watch's `skipToIndex:<n>` command.
    ///
    /// `n` is **relative to the track after the current one**, the same mapping CarPlay's Up Next
    /// uses: row `n` is absolute `currentIndex + 1 + n`. Unchanged by this migration.
    static func skipToIndexAbsolute(currentIndex: Int, relative: Int) -> Int {
        currentIndex + 1 + relative
    }

    /// Execute `skipToIndex:<relative>`.
    ///
    /// Preserved exactly, including two details that look like oversights but are existing
    /// behaviour and are not this lane's to change:
    ///
    /// - it calls `play(song:from:at:)` rather than `skipToIndex(_:)`, so the queue is re-seeded
    ///   with itself at the target position;
    /// - it guards only the **upper** bound. A negative `relative` large enough to drive the
    ///   absolute index below zero would subscript the queue out of range. Our own watch app only
    ///   ever sends row indices ≥ 0, so it is unreachable in practice — but it is a real gap and is
    ///   recorded in the migration inventory rather than silently patched here.
    static func skipToIndex(relative: Int) {
        let playback = playback
        let absolute = skipToIndexAbsolute(currentIndex: playback.currentIndex, relative: relative)
        guard absolute < playback.queue.count else { return }
        playback.play(song: playback.queue[absolute], from: playback.queue, at: absolute)
    }

    // MARK: - Outbound state

    /// The Now Playing payload sent to the Watch.
    ///
    /// Built fresh on every send: every value below is read at call time, so a queue or track change
    /// appears in the next update rather than in a snapshot taken when the manager was constructed.
    /// **Key names and value types are the wire contract with the Watch app** — `title`, `artist`,
    /// `album`, `isPlaying`, `elapsed`, `duration`, `isStarred`, `isShuffleOn`, `repeatMode`,
    /// `sleepTimerActive`, `queue` — and must not be renamed or restructured.
    static func nowPlayingContext(
        title: String, artist: String, album: String, isPlaying: Bool
    ) -> [String: Any] {
        let playback = playback
        var context: [String: Any] = [
            "title": title,
            "artist": artist,
            "album": album,
            "isPlaying": isPlaying,
            "elapsed": playback.currentTime,
            "duration": playback.duration,
            "isStarred": playback.currentSong?.starred != nil,
            "isShuffleOn": playback.shuffleEnabled,
            "repeatMode": repeatModeString(playback.repeatMode),
            "sleepTimerActive": SleepTimer.shared.isActive,
        ]
        // Up next, capped at 20 — the linear tail, matching what the Watch queue list expects.
        let upNext = playback.upNext.prefix(20)
        context["queue"] = upNext.map { ["title": $0.title, "artist": $0.displayArtist ?? ""] }
        return context
    }

    /// The lighter payload used for play/pause ticks.
    static func playbackStateContext(isPlaying: Bool) -> [String: Any] {
        [
            "isPlaying": isPlaying,
            "elapsed": playback.currentTime,
            "sleepTimerActive": SleepTimer.shared.isActive,
        ]
    }

    static func repeatModeString(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: "off"
        case .all: "all"
        case .one: "one"
        }
    }
}
#endif
