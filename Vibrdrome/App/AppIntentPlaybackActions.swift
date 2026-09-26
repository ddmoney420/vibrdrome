import Foundation

/// The playback operations Siri and Shortcuts trigger, separated from intent metadata.
///
/// **Execution context, verified rather than assumed.** `AppIntents.swift` has exactly one build
/// membership — the `Vibrdrome` app target. The project has no App Intents extension target (the
/// only extension is `VibrdromeWidget`, whose sources are `VibrdromeWidget` + `Shared`). So these
/// intents are compiled into the main app binary and run in the app's own process, which is why
/// resolving `ApplicationPlayback.shared` here reaches the same playback authority the UI uses.
/// There is no process boundary to bridge and no IPC to invent.
///
/// That holds for the two intents with `openAppWhenRun = false` as well: those run without
/// foregrounding the app, but still inside it.
///
/// An `enum` of static members, so an `AppIntent` value — which the system creates, copies and
/// discards freely — never retains a playback object and never carries cached state across
/// invocations. Same seam shape as `RemoteCommandManager`, `CarPlayPlaybackActions` and
/// `WatchPlaybackActions`.
@MainActor
enum AppIntentPlaybackActions {

    #if DEBUG
    /// Test seam. The real transport members would start AVQueuePlayer, which cannot happen while
    /// the gapless real-time suites are running. Tests substitute a recorder and reset it in
    /// teardown. Production never sets this, and it does not exist in release builds. It changes no
    /// intent metadata and no runtime registration.
    static var playbackOverride: (any ApplicationPlaybackControlling)?
    #endif

    /// Resolved during `perform()`, never at intent initialisation — the system may build an intent
    /// value long before it runs, and a snapshot taken then would be stale by the time it did.
    static var playback: any ApplicationPlaybackControlling {
        #if DEBUG
        playbackOverride ?? ApplicationPlayback.shared
        #else
        ApplicationPlayback.shared
        #endif
    }

    /// Start `song` with `queue` as the new queue, at index 0 — the form all three
    /// play-a-collection intents use.
    static func play(song: Song, from queue: [Song]) {
        playback.play(song: song, from: queue)
    }

    static func startRadio(artistName: String) {
        playback.startRadio(artistName: artistName)
    }

    static func togglePlayPause() {
        playback.togglePlayPause()
    }

    static func skipToNextTrack() {
        playback.next()
    }
}
