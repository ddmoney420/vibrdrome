#if os(iOS)
import Foundation

/// The playback-facing work the CarPlay scene does when a head unit connects.
///
/// **Scope is deliberately narrow.** Scene ownership stays in `CarPlaySceneDelegate`: the
/// `CPInterfaceController`, the `CarPlayManager` lifetime, teardown, and the order in which those
/// happen. Only the last step of `didConnect` — sync Now Playing, or restore the saved queue — lives
/// here, because it is the only part that touches playback and the only part a test can reach.
///
/// **Why it is extracted at all.** `CPInterfaceController` and `CPTemplateApplicationScene` have no
/// public initialisers, so `templateApplicationScene(_:didConnect:)` cannot be invoked from a test.
/// Without this split, "connecting CarPlay must not start audible playback" would be a claim with
/// nothing behind it.
///
/// Same seam shape as `CarPlayPlaybackActions`, `WatchPlaybackActions`, `RemoteCommandManager` and
/// `AppIntentPlaybackActions` — one pattern for "external event → named method → façade". Not
/// CarPlay-gated, because it imports no CarPlay symbols and must stay visible to the test target.
@MainActor
enum CarPlayScenePlaybackActions {

    /// Which branch the connect-time sync took. Returned so a test can pin the branch without
    /// inspecting `MPNowPlayingInfoCenter` global state.
    enum ConnectOutcome: Equatable {
        /// Something was already loaded; Now Playing was refreshed for the head unit.
        case refreshedNowPlaying
        /// Nothing was loaded; the saved queue restore was requested.
        case requestedQueueRestore
    }

    #if DEBUG
    /// Test seam. Defaults to `nil` and falls back to the composition point. It does not exist in
    /// release builds, and it alters no scene registration, no `CPInterfaceController` ownership and
    /// no template setup — it only changes which playback object this file talks to.
    static var playbackOverride: (any ApplicationPlaybackControlling)?
    #endif

    /// Resolved per call, never stored — CarPlay must see live playback state on every connection.
    static var playback: any ApplicationPlaybackControlling {
        #if DEBUG
        playbackOverride ?? ApplicationPlayback.shared
        #else
        ApplicationPlayback.shared
        #endif
    }

    /// The final step of CarPlay scene connection, unchanged in behaviour.
    ///
    /// If a track is already loaded, Now Playing is refreshed so the head unit shows current state.
    /// If nothing is loaded, the saved queue restore is requested.
    ///
    /// **Connecting CarPlay must never begin audible playback**, and this does not: it either writes
    /// Now Playing metadata, or calls `restorePlayQueue`, which restores a *paused* queue. That
    /// function deliberately does not activate the audio session and never calls `play()` — the rate
    /// stays at 0 — precisely so plugging in a phone cannot interrupt whatever the car was already
    /// playing (#134).
    ///
    /// Runs on **every** CarPlay connection, as before. It is naturally self-limiting rather than
    /// once-only: the `currentSong` check skips restore whenever anything is loaded, and
    /// `restorePlayQueue` itself returns early unless the current song, radio station and queue are
    /// all empty. A reconnect therefore cannot double-restore or disturb a queue already in place.
    @discardableResult
    static func syncNowPlayingOrRestoreQueue(client: SubsonicClient) -> ConnectOutcome {
        let playback = playback
        if let song = playback.currentSong {
            NowPlayingManager.shared.update(song: song, isPlaying: playback.isPlaying)
            NowPlayingManager.shared.updateElapsedTime(playback.currentTime)
            return .refreshedNowPlaying
        }
        playback.restorePlayQueue(client: client)
        return .requestedQueueRestore
    }
}
#endif
