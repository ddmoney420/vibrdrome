import AVFoundation
import AppIntents
import Foundation
import Testing
@testable import Vibrdrome

/// Lane 2C-C: the Siri / Shortcuts intents now reach playback through `ApplicationPlayback.shared`.
///
/// **Execution context, established from target membership rather than assumed.** `AppIntents.swift`
/// has exactly one build membership — the `Vibrdrome` app target — and the project contains no App
/// Intents extension target. The intents therefore run *inside the app process*, which is why
/// resolving the composition point reaches the same playback authority the UI uses. The two intents
/// with `openAppWhenRun = false` run without foregrounding the app, but still inside it. Nothing
/// here needs to cross a process boundary.
///
/// **No intent reads or returns playback state.** All six return a bare `.result()` with no dialog
/// and no snippet, so there is no state-bearing response surface to keep fresh — and this lane did
/// not invent one. What is verified instead is that the *seam* resolves during `perform()` rather
/// than when the intent value is built, since the system creates intent values freely and may run
/// them much later.
///
/// **No real audio.** `togglePlayPause` and `next` would start AVQueuePlayer, so the two intents
/// that call them are performed against an injected recorder.
@Suite(.serialized)
@MainActor
struct AppIntentPlaybackMigrationTests {

    private func makeSong(id: String, title: String = "Probe") -> Song {
        Song(
            id: id, parent: nil, title: title,
            album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
            track: nil, year: nil, genre: nil, coverArt: nil,
            size: nil, contentType: nil, suffix: nil,
            duration: 180, bitRate: nil, path: nil,
            discNumber: nil, created: nil, starred: nil, userRating: nil,
            bpm: nil, replayGain: nil, musicBrainzId: nil
        )
    }

    private func withRecorder(_ body: (PlaybackSpy) -> Void) {
        let spy = PlaybackSpy()
        AppIntentPlaybackActions.playbackOverride = spy
        defer { AppIntentPlaybackActions.playbackOverride = nil }
        body(spy)
    }

    // MARK: - Routing, end to end through perform()

    /// `TogglePlaybackIntent` and `SkipTrackIntent` touch nothing but playback — no `AppState`, no
    /// network — so their real `perform()` runs here. One invocation, one operation.
    @Test func transportIntentsDelegateExactlyOnceThroughPerform() async throws {
        let spy = PlaybackSpy()
        AppIntentPlaybackActions.playbackOverride = spy
        defer { AppIntentPlaybackActions.playbackOverride = nil }

        _ = try await TogglePlaybackIntent().perform()
        #expect(spy.calls == ["togglePlayPause"],
                "Toggle Playback produced \(spy.calls) instead of exactly one call")

        _ = try await SkipTrackIntent().perform()
        #expect(spy.calls == ["togglePlayPause", "next"],
                "Skip Track produced \(spy.calls)")
        #expect(spy.playCalls.isEmpty, "a transport intent started a new track")
    }

    /// Invoking the same intent repeatedly performs the operation once per invocation, never more.
    @Test func repeatedInvocationProducesOneOperationEach() async throws {
        let spy = PlaybackSpy()
        AppIntentPlaybackActions.playbackOverride = spy
        defer { AppIntentPlaybackActions.playbackOverride = nil }

        for _ in 0..<3 { _ = try await SkipTrackIntent().perform() }
        #expect(spy.calls == ["next", "next", "next"],
                "invocation count and operation count diverged: \(spy.calls)")
    }

    /// The action layer the collection intents use. Each delegates exactly once and nothing else;
    /// their `perform()` bodies are gated behind `AppState` and the network, so the operation they
    /// invoke is exercised directly here.
    @Test func eachIntentActionDelegatesExactlyOnce() {
        let songs = [makeSong(id: "a"), makeSong(id: "b")]

        withRecorder { spy in
            AppIntentPlaybackActions.play(song: songs[0], from: songs)
            #expect(spy.playCalls.count == 1, "play did not delegate exactly once")
            #expect(spy.playCalls.first?.songId == "a")
            #expect(spy.playCalls.first?.index == 0, "the collection intents must start at index 0")
            #expect(spy.calls.isEmpty)
        }
        withRecorder { spy in
            AppIntentPlaybackActions.startRadio(artistName: "Probe")
            #expect(spy.calls == ["startRadio"])
            #expect(spy.playCalls.isEmpty)
        }
        withRecorder { spy in
            AppIntentPlaybackActions.togglePlayPause()
            #expect(spy.calls == ["togglePlayPause"])
        }
        withRecorder { spy in
            AppIntentPlaybackActions.skipToNextTrack()
            #expect(spy.calls == ["next"])
        }
    }

    // MARK: - Double dispatch

    /// `TogglePlaybackIntent` and `SkipTrackIntent` expose the same semantic actions as the
    /// lock-screen play/pause and next buttons, but they are separate entry points. One invocation
    /// must travel one path.
    @Test func intentDoesNotAlsoDispatchThroughRemoteCommands() async throws {
        #expect(RemoteCommandManager.shared.playbackOverride == nil,
                "a previous test leaked a remote-command override")
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        let remoteSpy = PlaybackSpy()
        RemoteCommandManager.shared.playbackOverride = remoteSpy
        let intentSpy = PlaybackSpy()
        AppIntentPlaybackActions.playbackOverride = intentSpy
        defer {
            RemoteCommandManager.shared.playbackOverride = nil
            AppIntentPlaybackActions.playbackOverride = nil
        }

        _ = try await TogglePlaybackIntent().perform()
        _ = try await SkipTrackIntent().perform()

        #expect(intentSpy.calls == ["togglePlayPause", "next"])
        #expect(remoteSpy.calls.isEmpty,
                "an App Intent also dispatched through RemoteCommandManager")
        #expect(remoteSpy.playCalls.isEmpty)
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore,
                "performing an intent registered remote command handlers")
    }

    /// One invocation through the real production wiring produces exactly one legacy engine call.
    /// `toggleShuffle` is not an intent operation, so the count is taken on the intent's own
    /// façade resolution instead: the seam must be the shared adapter, not a private copy.
    @Test func intentSeamResolvesToTheProductionAdapter() {
        #expect(AppIntentPlaybackActions.playbackOverride == nil, "a previous test leaked an override")
        #expect(AppIntentPlaybackActions.playback === ApplicationPlayback.shared,
                "the intent layer resolved a second façade")
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the façade resolved to something other than the legacy adapter")
    }

    // MARK: - Freshness

    /// The seam resolves during `perform()`, not when the intent value is constructed. The system
    /// builds intent values freely and may run them much later, so a value captured at init would
    /// be stale — and, with the recorder installed after construction, simply wrong.
    @Test func seamResolvesDuringPerformNotAtIntentConstruction() async throws {
        let intent = SkipTrackIntent()          // built before any recorder exists
        let spy = PlaybackSpy()
        AppIntentPlaybackActions.playbackOverride = spy
        defer { AppIntentPlaybackActions.playbackOverride = nil }

        _ = try await intent.perform()

        #expect(spy.calls == ["next"],
                "the intent used a façade captured at construction time rather than at perform()")
    }

    /// Live state reached through the intent seam follows the engine rather than a cached copy.
    /// No intent returns state today; this guards the seam for when one does.
    @Test func stateReachedThroughTheIntentSeamIsLive() {
        let engine = AudioEngine.shared
        let contextBefore = engine.playingFromContext
        let queueBefore = engine.queue
        let indexBefore = engine.currentIndex
        defer {
            engine.playingFromContext = contextBefore
            engine.queue = queueBefore
            engine.currentIndex = indexBefore
        }

        let facade = AppIntentPlaybackActions.playback
        engine.queue = [makeSong(id: "s0"), makeSong(id: "s1")]
        engine.currentIndex = 0
        engine.playingFromContext = "intent probe"

        #expect(facade.queue.count == 2, "the intent seam is holding a stale queue snapshot")
        #expect(facade.currentIndex == 0)
        #expect(facade.playingFromContext == "intent probe")
        #expect(facade.currentSong?.id == engine.currentSong?.id)
        #expect(facade.isPlaying == engine.isPlaying)
    }

    // MARK: - Error and empty-state behaviour

    /// The four content intents refuse to run when no server is configured, and must still do so.
    /// This is the "app must be set up before playback can proceed" path, and it throws before any
    /// network call — so it is the one error path that is deterministic in a unit test.
    @Test func contentIntentsStillThrowWhenNotConfigured() async {
        let appState = AppState.shared
        let wasConfigured = appState.isConfigured
        appState.isConfigured = false
        defer { appState.isConfigured = wasConfigured }

        let spy = PlaybackSpy()
        AppIntentPlaybackActions.playbackOverride = spy
        defer { AppIntentPlaybackActions.playbackOverride = nil }

        await #expect(throws: IntentError.self) { _ = try await PlayFavoritesIntent().perform() }
        await #expect(throws: IntentError.self) { _ = try await PlayRandomMixIntent().perform() }
        await #expect(throws: IntentError.self) { _ = try await PlayArtistRadioIntent().perform() }
        await #expect(throws: IntentError.self) { _ = try await PlayPlaylistIntent().perform() }

        #expect(spy.calls.isEmpty, "an unconfigured intent still performed a playback operation")
        #expect(spy.playCalls.isEmpty, "an unconfigured intent still started a track")
    }

    /// Transport intents deliberately have **no** configuration guard — pausing what is already
    /// playing must work whether or not a server is reachable. Preserved exactly.
    @Test func transportIntentsRunWithoutAServerConfigured() async throws {
        let appState = AppState.shared
        let wasConfigured = appState.isConfigured
        appState.isConfigured = false
        defer { appState.isConfigured = wasConfigured }

        let spy = PlaybackSpy()
        AppIntentPlaybackActions.playbackOverride = spy
        defer { AppIntentPlaybackActions.playbackOverride = nil }

        _ = try await TogglePlaybackIntent().perform()
        _ = try await SkipTrackIntent().perform()
        #expect(spy.calls == ["togglePlayPause", "next"],
                "a transport intent gained a configuration guard it did not have")
    }

    /// The user-visible failure messages are part of the intent contract.
    @Test func intentErrorMessagesAreUnchanged() {
        #expect(String(localized: IntentError.notConfigured.localizedStringResource)
                == "Vibrdrome is not connected to a server. Open the app to sign in.")
        #expect(String(localized: IntentError.noContent.localizedStringResource)
                == "No songs found.")
        #expect(String(localized: IntentError.playlistNotFound.localizedStringResource)
                == "No playlist with that name was found.")
    }

    // MARK: - Contract preservation

    /// Titles, descriptions and launch policy are what Siri and the Shortcuts app key off. A
    /// playback-routing change must not disturb any of them.
    @Test func intentMetadataIsUnchanged() {
        #expect(String(localized: PlayFavoritesIntent.title) == "Play Favorites")
        #expect(String(localized: PlayRandomMixIntent.title) == "Play Random Mix")
        #expect(String(localized: PlayArtistRadioIntent.title) == "Play Artist Radio")
        #expect(String(localized: TogglePlaybackIntent.title) == "Toggle Playback")
        #expect(String(localized: SkipTrackIntent.title) == "Skip Track")
        #expect(String(localized: PlayPlaylistIntent.title) == "Play Playlist")

        // The two transport intents run without foregrounding the app; the four content intents
        // open it. Flipping either would visibly change Siri's behaviour.
        #expect(PlayFavoritesIntent.openAppWhenRun)
        #expect(PlayRandomMixIntent.openAppWhenRun)
        #expect(PlayArtistRadioIntent.openAppWhenRun)
        #expect(PlayPlaylistIntent.openAppWhenRun)
        #expect(TogglePlaybackIntent.openAppWhenRun == false)
        #expect(SkipTrackIntent.openAppWhenRun == false)
    }

    /// The two string parameters still exist, still carry those names, and still round-trip.
    ///
    /// Deliberately set before reading: `@Parameter` holds no value until the system populates it,
    /// and reading it unset traps inside `IntentParameter` with "Non-optional value can not be nil".
    /// Shortcuts always assigns before invoking, so the unset state is not a case worth asserting —
    /// and asserting it takes the whole test process down.
    @Test func intentParametersAreUnchanged() {
        var radio = PlayArtistRadioIntent()
        radio.artistName = "Probe Artist"
        #expect(radio.artistName == "Probe Artist")

        var playlist = PlayPlaylistIntent()
        playlist.playlistName = "Probe Playlist"
        #expect(playlist.playlistName == "Probe Playlist")
    }

    /// The two phrase-backed shortcuts are still offered to Siri.
    @Test func appShortcutsAreStillProvided() {
        #expect(VibrdromeShortcuts.appShortcuts.count == 2,
                "the set of Siri phrase shortcuts changed")
    }

    // MARK: - Construction

    /// Building intent values must start nothing — the system constructs them during Shortcuts
    /// browsing, long before any invocation.
    @Test func constructingIntentsStartsNothing() {
        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let queueBefore = engine.queue.count
        let indexBefore = engine.currentIndex
        let categoryBefore = AVAudioSession.sharedInstance().category
        let modeBefore = AVAudioSession.sharedInstance().mode
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        for _ in 0..<100 {
            _ = PlayFavoritesIntent()
            _ = PlayRandomMixIntent()
            _ = PlayArtistRadioIntent()
            _ = TogglePlaybackIntent()
            _ = SkipTrackIntent()
            _ = PlayPlaylistIntent()
            _ = VibrdromeShortcuts.appShortcuts
            #expect(AppIntentPlaybackActions.playback === ApplicationPlayback.shared,
                    "a second façade was created")
        }

        #expect(engine.isPlaying == playingBefore, "constructing an intent started playback")
        #expect(engine.queue.count == queueBefore)
        #expect(engine.currentIndex == indexBefore)
        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "constructing an intent configured the audio session")
        #expect(AVAudioSession.sharedInstance().mode == modeBefore)
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore,
                "constructing an intent registered remote command handlers")
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "constructing an intent built a persistent playback controller")
    }

    /// The DEBUG override defaults to nil, falls back to the composition point, and is restored.
    @Test func testSeamDefaultsToProductionWiring() {
        #expect(AppIntentPlaybackActions.playbackOverride == nil,
                "the intent façade override leaked out of a previous test")
        #expect(AppIntentPlaybackActions.playback === ApplicationPlayback.shared)

        withRecorder { spy in
            #expect(AppIntentPlaybackActions.playback === spy)
        }
        #expect(AppIntentPlaybackActions.playback === ApplicationPlayback.shared,
                "the override was not restored after use")
    }

    /// Lane 2C-C moves one file. The persistent engine stays unwired.
    @Test func persistentPlaybackRemainsUnwired() {
        #expect(GaplessDiagnosticsRegistry.current == nil)
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the façade resolved to something other than the legacy adapter")
    }
}
