import Foundation
import Observation
import Testing
@testable import Vibrdrome

#if os(iOS)
import AVFoundation
#endif

/// Lane 2A phase 3: the view layer now reaches playback through `ApplicationPlayback.shared`
/// instead of `AudioEngine.shared`.
///
/// The migration is behaviour-preserving by construction — every façade member is a one-line
/// forward to the same singleton — so what these tests defend is the part a diff review cannot
/// see:
///
/// 1. **Observation still works.** A migrated view re-renders because *reading* a façade property
///    registers a dependency on the `@Observable` engine inside the caller's tracking scope. If
///    that stopped being true, every migrated view would quietly freeze and no build would fail.
/// 2. **One user action is still exactly one engine call.** Forwarding twice doubles a command
///    (the defect class that makes a button skip two tracks); forwarding zero times drops it.
/// 3. **The seam stays a seam.** No second engine, no second queue, nothing started at view
///    construction.
///
/// **Nothing here starts real audio.** These suites run alongside the gapless real-time suites,
/// and two engines contending for the audio stack killed the test process three times during
/// Lane 1. So transport members that would begin playback (`play`, `next`, `skipToIndex`, …) are
/// exercised against a protocol conformer, never the live engine. The members that *are* driven
/// against the live adapter were each read first and confirmed to be guarded no-ops when nothing
/// is playing — `seek` returns before touching a player when `effectiveDuration` is 0,
/// `removeFromQueue` rejects an out-of-range index, `moveInUpNext` returns on an empty queue, and
/// the metadata updaters match no row for an unknown id.
@Suite(.serialized)
@MainActor
struct ApplicationPlaybackMigrationTests {

    // MARK: - Helpers

    private func makeSong(id: String = "probe-1", title: String = "Probe") -> Song {
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

    /// Records whether Observation fired, from the `@Sendable` `onChange` closure.
    private final class ObservationProbe: @unchecked Sendable {
        var fired = false
    }

    // MARK: - Observation

    /// The load-bearing property of the whole migration.
    ///
    /// `LegacyAudioEngineAdapter.currentSong` is `{ engine.currentSong }` — a computed
    /// read-through. The access therefore happens on the `@Observable` `AudioEngine` *while the
    /// caller's tracking scope is open*, so the dependency is registered against the engine's
    /// property, not against the façade. The negative half matters as much as the positive half:
    /// a façade that over-registered would invalidate views on every unrelated engine change.
    @Test func facadeReadsRegisterObservationDependenciesOnTheEngine() {
        let engine = AudioEngine.shared
        let originalContext = engine.playingFromContext
        let originalVisualizer = engine.visualizerActive
        defer {
            engine.playingFromContext = originalContext
            engine.visualizerActive = originalVisualizer
        }

        let probe = ObservationProbe()
        withObservationTracking {
            // Read through the façade exactly as a migrated view body does.
            _ = ApplicationPlayback.shared.playingFromContext
        } onChange: {
            probe.fired = true
        }

        // Negative control: an unrelated engine property must not invalidate this scope.
        engine.visualizerActive = !originalVisualizer
        #expect(probe.fired == false,
                "reading one façade property registered a dependency on an unrelated one")

        // Positive: mutating the property that was read through the façade must fire.
        engine.playingFromContext = "lane2a-observation-probe"
        #expect(probe.fired,
                "a façade read registered no Observation dependency; migrated views would freeze")
    }

    /// Observation also has to survive the *aliased* form the views actually use:
    /// `private var engine: any ApplicationPlaybackControlling { ApplicationPlayback.shared }`,
    /// then `engine.currentSong`. Going through an existential must not box away the tracking.
    @Test func observationSurvivesTheExistentialAlias() {
        let engine = AudioEngine.shared
        let original = engine.playingFromContext
        defer { engine.playingFromContext = original }

        let playback: any ApplicationPlaybackControlling = ApplicationPlayback.shared
        let probe = ObservationProbe()
        withObservationTracking {
            _ = playback.playingFromContext
        } onChange: {
            probe.fired = true
        }

        engine.playingFromContext = "lane2a-existential-probe"
        #expect(probe.fired,
                "reading through `any ApplicationPlaybackControlling` lost Observation tracking")
    }

    // MARK: - Read-through of the Lane 2A surface

    /// Phase 1 added 13 members so the views would have somewhere to land. Each must read the
    /// singleton rather than hold a copy — a copy would drift the moment anything still calling
    /// `AudioEngine.shared` directly (CarPlay, Watch, Siri, the scene entry) mutated it.
    @Test func laneTwoSurfaceReadsThroughToTheSingleton() {
        let engine = AudioEngine.shared
        let facade = ApplicationPlayback.shared

        #expect(facade.currentSong?.id == engine.currentSong?.id)
        #expect(facade.currentTime == engine.currentTime)
        #expect(facade.smoothCurrentTime == engine.smoothCurrentTime)
        #expect(facade.isBuffering == engine.isBuffering)
        #expect(facade.duration == engine.duration)
        #expect(facade.effectiveDuration == engine.effectiveDuration)
        #expect(facade.upNextEntries.count == engine.upNextEntries.count)
        #expect(facade.nextSongIndex() == engine.nextSongIndex())
        #expect(facade.radioSeedArtistName == engine.radioSeedArtistName)
        #expect(facade.eqEnabled == engine.eqEnabled)
        #expect(facade.userVolume == engine.userVolume)
        #expect(facade.volume == engine.volume)
        #expect(facade.playbackRate == engine.playbackRate)
        #expect(facade.visualizerActive == engine.visualizerActive)
        #expect(facade.predownloadsPending == engine.predownloadsPending)
        #expect(facade.predownloadSpeed == engine.predownloadSpeed)
        #expect(facade.recentlyPlayed.count == engine.recentlyPlayed.count)
    }

    // MARK: - Convenience overload

    /// `play(song:from:)` is the form ~40 migrated call sites use, and it is the only piece of
    /// real logic in the contract: a protocol requirement cannot carry a default argument, so the
    /// two-argument form lives in an extension that must delegate **once**, at index 0. A spy is
    /// used rather than the live engine because the real `play` starts AVQueuePlayer.
    @Test func conveniencePlayDelegatesExactlyOnceAtIndexZero() {
        let spy = PlaybackSpy()
        let songs = [makeSong(id: "a"), makeSong(id: "b")]

        spy.play(song: songs[0], from: songs)

        #expect(spy.playCalls.count == 1, "the convenience overload did not delegate exactly once")
        #expect(spy.playCalls.first?.songId == "a")
        #expect(spy.playCalls.first?.queueCount == 2)
        #expect(spy.playCalls.first?.index == 0,
                "the convenience overload must start at index 0")
        #expect(spy.calls.isEmpty, "the convenience overload invoked an unrelated member")
    }

    /// The representative actions of the migrated views, each expressed against the contract the
    /// views now hold. These are the members that would start real audio or real network traffic
    /// against the live engine, so they are proven at the protocol level: one call in, one call
    /// recorded, nothing else touched.
    @Test func representativeViewActionsDelegateExactlyOnce() {
        let song = makeSong()
        let queue = [song]

        // Mini player: play/pause, next, previous. Queue view / side panel: tap a row.
        // Album, playlist, track row: play a track, queue a track, start radio from a track.
        let cases: [(name: String, action: @MainActor (PlaybackSpy) -> Void)] = [
            ("togglePlayPause", { $0.togglePlayPause() }),
            ("next", { $0.next() }),
            ("previous", { $0.previous() }),
            ("skipToIndex", { $0.skipToIndex(3) }),
            ("play", { $0.play(song: song, from: queue, at: 0) }),
            ("addToQueue", { $0.addToQueue(song) }),
            ("addToQueueNext", { $0.addToQueueNext(song) }),
            ("clearQueue", { $0.clearQueue() }),
            ("startRadio", { $0.startRadio(artistName: "Probe") }),
            ("startRadioFromSong", { $0.startRadioFromSong(song) }),
            ("startSongSimilarityMix", { $0.startSongSimilarityMix(song) }),
            ("stopRadioMode", { $0.stopRadioMode() }),
            ("toggleShuffle", { $0.toggleShuffle() }),
            ("cycleRepeatMode", { $0.cycleRepeatMode() }),
            ("seek", { $0.seek(to: 30) })
        ]

        for testCase in cases {
            let spy = PlaybackSpy()
            testCase.action(spy)
            let recorded = spy.calls + spy.playCalls.map { _ in "play" }
            #expect(recorded == [testCase.name],
                    "\(testCase.name) did not produce exactly one delegated call: \(recorded)")
        }
    }

    // MARK: - Live adapter delegation (audio-safe members only)

    /// The seek path a migrated slider drives. `AudioEngine.seek` returns before touching any
    /// player when `effectiveDuration` is 0, so this counts the delegation without moving audio.
    @Test func seekDelegatesExactlyOnceWithoutChangingState() {
        guard let adapter = ApplicationPlayback.legacyAdapter else {
            Issue.record("the façade did not resolve to the legacy adapter")
            return
        }
        let engine = AudioEngine.shared
        adapter.resetDelegationCounts()

        let queueBefore = engine.queue.count
        let indexBefore = engine.currentIndex
        let playingBefore = engine.isPlaying

        adapter.seek(to: 30)

        #expect(adapter.delegatedCallCounts["seek"] == 1)
        #expect(engine.queue.count == queueBefore)
        #expect(engine.currentIndex == indexBefore)
        #expect(engine.isPlaying == playingBefore, "a delegated seek started playback")
        adapter.resetDelegationCounts()
    }

    /// The EQ switch in `PlayerSettingsView`, which now writes through the façade.
    @Test func eqToggleDelegatesExactlyOnceAndReachesTheSingleton() {
        guard let adapter = ApplicationPlayback.legacyAdapter else {
            Issue.record("the façade did not resolve to the legacy adapter")
            return
        }
        let engine = AudioEngine.shared
        let original = engine.eqEnabled
        defer { engine.applyEQToggle(enabled: original) }
        adapter.resetDelegationCounts()

        adapter.applyEQToggle(enabled: !original)

        #expect(adapter.delegatedCallCounts["applyEQToggle"] == 1)
        #expect(engine.eqEnabled == !original, "the EQ toggle did not reach the singleton")
        #expect(ApplicationPlayback.shared.eqEnabled == engine.eqEnabled)
        adapter.resetDelegationCounts()
    }

    /// The macOS player-bar volume slider binds `get`/`set` straight onto the façade. The write
    /// has to land on the one engine the rest of the app is still reading.
    @Test func volumeWritesReachTheSingletonExactlyOnce() {
        let engine = AudioEngine.shared
        let original = engine.userVolume
        defer { engine.userVolume = original }

        ApplicationPlayback.shared.userVolume = 0.42
        #expect(abs(engine.userVolume - 0.42) < 0.0001,
                "a façade volume write did not reach AudioEngine")
        #expect(abs(ApplicationPlayback.shared.userVolume - 0.42) < 0.0001)

        // `volume` is the ReplayGain-scaled setter and clamps; it must clamp on the singleton too.
        ApplicationPlayback.shared.volume = 2.0
        #expect(engine.userVolume == 1.0, "the clamped volume setter did not reach AudioEngine")
    }

    /// Queue mutations a migrated view can trigger: the queue-row swipe-to-remove and the Up Next
    /// reorder, plus the heart and star buttons in the track row and player bar. Each argument is
    /// chosen so the engine's own guard makes the call a no-op — the delegation is what is under
    /// test, not the mutation.
    @Test func queueMutationsDelegateExactlyOnceWithoutMutatingState() {
        guard let adapter = ApplicationPlayback.legacyAdapter else {
            Issue.record("the façade did not resolve to the legacy adapter")
            return
        }
        let engine = AudioEngine.shared
        adapter.resetDelegationCounts()

        let queueBefore = engine.queue.map(\.id)
        let indexBefore = engine.currentIndex

        adapter.removeFromQueue(atAbsolute: Int.max)          // out of range → guarded no-op
        adapter.moveInUpNext(from: IndexSet(), to: 0)         // empty move → guarded no-op
        adapter.updateQueueSongStarred(id: "lane2a-absent", starred: true)
        adapter.updateQueueSongRating(id: "lane2a-absent", rating: 5)

        #expect(adapter.delegatedCallCounts["removeFromQueue"] == 1)
        #expect(adapter.delegatedCallCounts["moveInUpNext"] == 1)
        #expect(adapter.delegatedCallCounts["updateQueueSongStarred"] == 1)
        #expect(adapter.delegatedCallCounts["updateQueueSongRating"] == 1)
        #expect(engine.queue.map(\.id) == queueBefore, "a delegated no-op changed the queue")
        #expect(engine.currentIndex == indexBefore)
        adapter.resetDelegationCounts()
    }

    /// `playingFromContext` is the one read-write application concept on the façade — playlist and
    /// home views set it alongside starting playback. It must not become a second copy.
    @Test func playingFromContextWritesReachTheSingleton() {
        let engine = AudioEngine.shared
        let original = engine.playingFromContext
        defer { engine.playingFromContext = original }

        ApplicationPlayback.shared.playingFromContext = "Playlist: Lane 2A"
        #expect(engine.playingFromContext == "Playlist: Lane 2A")

        engine.playingFromContext = "Random Mix"
        #expect(ApplicationPlayback.shared.playingFromContext == "Random Mix",
                "the façade returned a stale copy instead of reading the engine")
    }

    // MARK: - View construction

    /// Build 60's cold-launch behaviour depends on nothing waking the audio stack before an
    /// explicit Play. Constructing a migrated view resolves `ApplicationPlayback.shared` for the
    /// first time in some launches, so construction must stay inert.
    @Test func migratedViewConstructionStartsNothing() {
        let engine = AudioEngine.shared
        let wasPlaying = engine.isPlaying
        let queueBefore = engine.queue.count
        let indexBefore = engine.currentIndex
        #if os(iOS)
        let categoryBefore = AVAudioSession.sharedInstance().category
        let modeBefore = AVAudioSession.sharedInstance().mode
        #endif

        _ = MiniPlayerView()
        _ = QueueView()
        _ = BookmarksView()
        _ = RadioView()

        #expect(engine.isPlaying == wasPlaying, "constructing a migrated view started playback")
        #expect(engine.queue.count == queueBefore, "constructing a migrated view changed the queue")
        #expect(engine.currentIndex == indexBefore)
        #if os(iOS)
        // Configuring the session is what sets these; an unchanged pair means no view reached for
        // `AudioSessionManager` on the way up.
        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "constructing a migrated view configured the audio session")
        #expect(AVAudioSession.sharedInstance().mode == modeBefore)
        #endif
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "constructing a migrated view built a persistent playback controller")
    }

    /// SwiftUI rebuilds view structs constantly. Each rebuild re-resolves the composition point,
    /// which must keep handing back the same façade — a second one would mean a second set of
    /// observers, remote-command registrations and Now Playing writers.
    @Test func viewReconstructionDoesNotDuplicateTheFacade() {
        let first = ApplicationPlayback.shared
        for _ in 0..<200 {
            _ = MiniPlayerView()
            _ = QueueView()
            #expect(ApplicationPlayback.shared === first)
        }
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the façade stopped resolving to the legacy adapter")
    }

    /// Lane 2A moves call sites only. The production path must still be
    /// views → façade → `LegacyAudioEngineAdapter` → `AudioEngine.shared` → AVQueuePlayer, with
    /// the persistent PCM controller never constructed by the application.
    @Test func persistentPlaybackRemainsUnwiredAfterMigration() {
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "the application constructed a persistent playback controller")
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the façade resolved to something other than the legacy adapter")
    }
}

// MARK: - Spy

/// Records calls without performing them.
///
/// Exists so the transport, queue and radio members can be proven to delegate exactly once
/// *without* starting AVQueuePlayer, a live radio stream or a predownload. It conforms to the full
/// application contract so any future lane can reuse it.
@MainActor
final class PlaybackSpy: ApplicationPlaybackControlling {
    /// Every non-`play` member call, in order.
    private(set) var calls: [String] = []
    /// `play` is recorded separately because its arguments are the thing under test.
    private(set) var playCalls: [(songId: String, queueCount: Int?, index: Int)] = []

    private func record(_ name: String) { calls.append(name) }

    // Transport
    func play(song: Song, from queue: [Song]?, at index: Int) {
        playCalls.append((song.id, queue?.count, index))
    }
    func pause() { record("pause") }
    func resume() { record("resume") }
    func stop() { record("stop") }
    func togglePlayPause() { record("togglePlayPause") }
    func next() { record("next") }
    func previous() { record("previous") }
    func seek(to time: TimeInterval) { record("seek") }
    func skipToIndex(_ index: Int) { record("skipToIndex") }

    // Queue
    func addToQueue(_ song: Song) { record("addToQueue") }
    func addToQueue(_ songs: [Song]) { record("addToQueue") }
    func addToQueueNext(_ song: Song) { record("addToQueueNext") }
    func addToQueueNext(_ songs: [Song]) { record("addToQueueNext") }
    func updateQueueSongStarred(id: String, starred: Bool) { record("updateQueueSongStarred") }
    func updateQueueSongRating(id: String, rating: Int?) { record("updateQueueSongRating") }
    func clearQueue() { record("clearQueue") }
    func removeFromQueue(atAbsolute index: Int) { record("removeFromQueue") }
    func moveInUpNext(from source: IndexSet, to destination: Int) { record("moveInUpNext") }

    // State
    var isPlaying = false
    /// Counts reads of `currentSong`, so a caller can be proven to re-read it on every use rather
    /// than caching a copy that would go stale the moment the track changed.
    private(set) var currentSongReads = 0
    private var storedCurrentSong: Song?
    var currentSong: Song? {
        get {
            currentSongReads += 1
            return storedCurrentSong
        }
        set { storedCurrentSong = newValue }
    }
    var currentTime: TimeInterval = 0
    var smoothCurrentTime: TimeInterval = 0
    var isBuffering = false
    var duration: TimeInterval = 0
    var effectiveDuration: TimeInterval = 0
    var queue: [Song] = []
    var currentIndex = 0
    var upNextEntries: [(index: Int, song: Song)] = []
    func nextSongIndex() -> Int? { nil }
    var playingFromContext: String?

    // Modes
    var shuffleEnabled = false
    var repeatMode: RepeatMode = .off
    func toggleShuffle() { record("toggleShuffle") }
    func cycleRepeatMode() { record("cycleRepeatMode") }

    // Radio
    var isRadioMode = false
    var currentRadioStation: InternetRadioStation?
    var radioSeedArtistName: String?
    func startRadio(artistName: String) { record("startRadio") }
    func startRadioFromSong(_ song: Song) { record("startRadioFromSong") }
    func startSongSimilarityMix(_ song: Song) { record("startSongSimilarityMix") }
    func playRadio(station: InternetRadioStation) { record("playRadio") }
    func stopRadioMode() { record("stopRadioMode") }

    // Processing
    var eqEnabled = false
    var volume: Float = 1
    var userVolume: Float = 1
    var playbackRate: Float = 1
    var visualizerActive = false
    func applyEQToggle(enabled: Bool) { record("applyEQToggle") }
    func applyEffectiveVolume() { record("applyEffectiveVolume") }

    // Predownload
    var predownloadStatus: PredownloadStatus = .idle
    var predownloadSpeed: Double = 0
    var predownloadsPending = 0
    func prepareLookahead() { record("prepareLookahead") }

    // History
    var recentlyPlayed: [Song] = []
    func addRandomSongPlayed(songId: String) { record("addRandomSongPlayed") }
    func restorePlayQueue(client: SubsonicClient) { record("restorePlayQueue") }
}
