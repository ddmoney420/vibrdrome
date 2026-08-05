import Foundation

/// The playback operations the app entry point triggers, separated from scene declaration.
///
/// **Named for commands, not lifecycle, because that is what the audit found.** Every playback
/// reference in `Vibrdrome.swift` sits behind an explicit user action — a `vibrdrome://song/<id>`
/// deep link, or a macOS Playback-menu item with a keyboard shortcut. `VibrdromeApp.init()` and the
/// scenes' `.onAppear` touch playback **not at all**: they run migrations, register background
/// tasks, install the image pipeline, set up remote commands and start library sync. Queue
/// restoration lives in `ContentView` / `MacContentView` (Lane 2D-B1) and `CarPlaySceneDelegate`
/// (Lane 2D-A), not here.
///
/// So there is no cold-launch playback path in this file to protect — and calling this type
/// "lifecycle" would encode a launch-phase relationship that does not exist.
///
/// It is an `enum` of static members so the SwiftUI `Button` closures reference it exactly as they
/// referenced `AudioEngine.shared`: no closure gains a capture, and `PlaybackCommands` — a `View`
/// value SwiftUI recreates freely — holds nothing. Same seam shape as the other five.
@MainActor
enum AppCommandPlaybackActions {

    #if DEBUG
    /// Test seam. `PlaybackCommands` is a private macOS-only `View` whose menu actions live inside
    /// `Button` closures, and a deep link cannot be delivered from a unit test, so the command
    /// bodies are only reachable here. Defaults to `nil`, absent from release builds, and changes no
    /// app registration, scene ownership or remote-command setup.
    static var playbackOverride: (any ApplicationPlaybackControlling)?
    #endif

    /// Resolved per command, never cached — a menu item may fire at any point in the app's life.
    static var playback: any ApplicationPlaybackControlling {
        #if DEBUG
        playbackOverride ?? ApplicationPlayback.shared
        #else
        ApplicationPlayback.shared
        #endif
    }

    // MARK: - Deep link

    /// `vibrdrome://song/<id>`. Starts the fetched song with no queue, at index 0 — the engine's
    /// own defaults, unchanged. The fetch happens first and a failure never reaches this call.
    static func playSong(_ song: Song) {
        playback.play(song: song)
    }

    // MARK: - macOS Playback menu

    static func togglePlayPause() { playback.togglePlayPause() }

    static func nextTrack() { playback.next() }

    static func previousTrack() { playback.previous() }

    /// Clamped to the track end, exactly as the menu item did.
    static func seekForward(by interval: TimeInterval) {
        let playback = playback
        playback.seek(to: min(playback.duration, playback.currentTime + interval))
    }

    /// Clamped to the track start, exactly as the menu item did.
    static func seekBackward(by interval: TimeInterval) {
        let playback = playback
        playback.seek(to: max(0, playback.currentTime - interval))
    }

    static func toggleShuffle() { playback.toggleShuffle() }

    static func cycleRepeatMode() { playback.cycleRepeatMode() }

    /// The call-site clamps are kept verbatim. The engine clamps to `0...1` as well, so these are
    /// belt-and-braces — but removing them would be a behaviour change this lane has no reason to
    /// make.
    static func volumeUp(by step: Float) {
        let playback = playback
        playback.volume = min(1, playback.volume + step)
    }

    static func volumeDown(by step: Float) {
        let playback = playback
        playback.volume = max(0, playback.volume - step)
    }

    /// The track the favourite and rating menu items act on. A read, not a transport operation:
    /// both commands are no-ops when nothing is loaded.
    static var currentSong: Song? { playback.currentSong }
}
