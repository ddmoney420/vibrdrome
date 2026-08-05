import SwiftUI

/// The playback half of scene-phase handling, separated from the view-local work that shares those
/// callbacks (widget commands, auto-sync, playlist export).
///
/// **iOS and macOS are deliberately not merged.** They save on *different phases*: iOS saves on
/// `.background`, macOS on `.inactive`, because a Mac window rarely reaches `.background` at all. A
/// shared handler would have to pick one and would silently stop saving on the other platform, so
/// there are two entry points and each is pinned by its own test.
///
/// Owns no scene state, registers no observers, creates no tasks of its own, and the `.onChange`
/// closures stay in the two view files.
@MainActor
enum ScenePlaybackLifecycleActions {

    /// What a scene-phase transition did to playback. Returned so tests can pin which phases act
    /// without reaching into the engine.
    enum LifecycleOutcome: Equatable {
        /// Queue persisted and a resume bookmark considered.
        case saved
        /// Saved queue restore requested and observable state re-synced.
        case restoredAndRefreshed
        /// A phase this platform does not act on.
        case none
    }

    #if DEBUG
    /// Test seam. Defaults to `nil` and falls back to the composition point; absent from release
    /// builds. It owns no scene state and changes no lifecycle registration.
    static var playbackOverride: (any ApplicationPlaybackControlling)?
    #endif

    /// Resolved per transition, never cached across scene phases.
    static var playback: any ApplicationPlaybackControlling {
        #if DEBUG
        playbackOverride ?? ApplicationPlayback.shared
        #else
        ApplicationPlayback.shared
        #endif
    }

    /// iOS scene-phase playback work. Saves on `.background`, restores on `.active`.
    @discardableResult
    static func handleIOSScenePhase(
        _ phase: ScenePhase, client: SubsonicClient
    ) -> LifecycleOutcome {
        switch phase {
        case .background: return save(client: client)
        case .active: return restore(client: client)
        default: return .none
        }
    }

    /// macOS scene-phase playback work. Saves on `.inactive` — a Mac window rarely gets
    /// `.background`, so waiting for it would mean never saving — and restores on `.active`.
    @discardableResult
    static func handleMacScenePhase(
        _ phase: ScenePhase, client: SubsonicClient
    ) -> LifecycleOutcome {
        switch phase {
        case .inactive: return save(client: client)
        case .active: return restore(client: client)
        default: return .none
        }
    }

    /// The save trio, in the order both platforms already used. No debounce or deduplication: a
    /// repeated qualifying phase saves again, exactly as before. The engine skips an empty queue, so
    /// a spurious transition cannot overwrite good server state with nothing.
    private static func save(client: SubsonicClient) -> LifecycleOutcome {
        let playback = playback
        playback.savePlayQueue(client: client)
        playback.saveQueueLocally()
        playback.createBookmarkIfNeeded(client: client)
        return .saved
    }

    /// Restore, then re-sync observable state — the order both platforms already used.
    ///
    /// This must not begin audible playback: `restorePlayQueue` restores a **paused** queue, never
    /// activating the audio session and never calling `play()` (#134). It is also one of three
    /// restore requesters, alongside `CarPlaySceneDelegate`; whichever arrives first restores and
    /// the engine's own guard makes the rest no-ops. No once-per-process rule is imposed here.
    private static func restore(client: SubsonicClient) -> LifecycleOutcome {
        let playback = playback
        playback.restorePlayQueue(client: client)
        playback.refreshPlaybackState()
        return .restoredAndRefreshed
    }
}
