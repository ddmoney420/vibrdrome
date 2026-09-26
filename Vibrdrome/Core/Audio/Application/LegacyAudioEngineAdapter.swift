import Foundation

/// The application playback façade, implemented entirely by delegating to `AudioEngine.shared`.
///
/// **This is a seam, not an implementation.** It owns no playback state, no queue, no timers and no
/// observers — every member forwards to the existing singleton, which remains the single authority.
/// Duplicating any of that here would create a second source of truth for the queue, and the two
/// would drift the moment anything touched the singleton directly. That matters right now, because
/// Lane 1 deliberately leaves all 194 existing direct call sites in place: the façade and the direct
/// callers must be looking at the same object, not at copies.
///
/// Its purpose is to give Lane 2 somewhere to migrate call sites *to*, and to give a future selector
/// one place to change. Behaviour is identical to calling the singleton, by construction.
@MainActor
final class LegacyAudioEngineAdapter: ApplicationPlaybackControlling {
    /// The single authority. Held as a computed property rather than stored, so there is no way for
    /// this adapter to end up pointing at a different engine than the direct callers do.
    private var engine: AudioEngine { AudioEngine.shared }

    /// Counts delegated calls in DEBUG, so a test can prove one façade call produces exactly one
    /// engine call — the property that makes "no behaviour change" checkable rather than asserted.
    #if DEBUG
    private(set) var delegatedCallCounts: [String: Int] = [:]
    private func count(_ name: String) { delegatedCallCounts[name, default: 0] += 1 }
    func resetDelegationCounts() { delegatedCallCounts.removeAll() }
    #else
    @inline(__always) private func count(_ name: String) {}
    #endif

    // MARK: - Transport

    func play(song: Song, from queue: [Song]?, at index: Int) {
        count("play")
        engine.play(song: song, from: queue, at: index)
    }
    func pause() { count("pause"); engine.pause() }
    func resume() { count("resume"); engine.resume() }
    func stop() { count("stop"); engine.stop() }
    func togglePlayPause() { count("togglePlayPause"); engine.togglePlayPause() }
    func next() { count("next"); engine.next() }
    func previous() { count("previous"); engine.previous() }
    func seek(to time: TimeInterval) { count("seek"); engine.seek(to: time) }
    func skipToIndex(_ index: Int) { count("skipToIndex"); engine.skipToIndex(index) }
    func handleMediaServicesReset() { count("handleMediaServicesReset"); engine.handleMediaServicesReset() }

    // MARK: - Queue

    func addToQueue(_ song: Song) { count("addToQueue"); engine.addToQueue(song) }
    func addToQueue(_ songs: [Song]) { count("addToQueue"); engine.addToQueue(songs) }
    func addToQueueNext(_ song: Song) { count("addToQueueNext"); engine.addToQueueNext(song) }
    func addToQueueNext(_ songs: [Song]) { count("addToQueueNext"); engine.addToQueueNext(songs) }
    func updateQueueSongStarred(id: String, starred: Bool) {
        count("updateQueueSongStarred")
        engine.updateQueueSongStarred(id: id, starred: starred)
    }
    func updateQueueSongRating(id: String, rating: Int?) {
        count("updateQueueSongRating")
        engine.updateQueueSongRating(id: id, rating: rating)
    }
    func clearQueue() { count("clearQueue"); engine.clearQueue() }
    func removeFromQueue(atAbsolute index: Int) {
        count("removeFromQueue")
        engine.removeFromQueue(atAbsolute: index)
    }
    func moveInUpNext(from source: IndexSet, to destination: Int) {
        count("moveInUpNext")
        engine.moveInUpNext(from: source, to: destination)
    }

    // MARK: - State

    var isPlaying: Bool { engine.isPlaying }
    var currentSong: Song? { engine.currentSong }
    var currentTime: TimeInterval { engine.currentTime }
    var smoothCurrentTime: TimeInterval { engine.smoothCurrentTime }
    var isBuffering: Bool { engine.isBuffering }
    var duration: TimeInterval { engine.duration }
    var effectiveDuration: TimeInterval { engine.effectiveDuration }
    var queue: [Song] { engine.queue }
    var currentIndex: Int { engine.currentIndex }
    var upNextEntries: [(index: Int, song: Song)] { engine.upNextEntries }
    var upNext: [Song] { engine.upNext }
    func nextSongIndex() -> Int? { engine.nextSongIndex() }
    var playingFromContext: String? {
        get { engine.playingFromContext }
        set { engine.playingFromContext = newValue }
    }

    // MARK: - Repeat and shuffle

    var shuffleEnabled: Bool { engine.shuffleEnabled }
    var repeatMode: RepeatMode { engine.repeatMode }
    func toggleShuffle() { count("toggleShuffle"); engine.toggleShuffle() }
    func cycleRepeatMode() { count("cycleRepeatMode"); engine.cycleRepeatMode() }

    // MARK: - Radio

    var isRadioMode: Bool { engine.isRadioMode }
    var currentRadioStation: InternetRadioStation? { engine.currentRadioStation }
    var radioSeedArtistName: String? { engine.radioSeedArtistName }
    func startRadio(artistName: String) { count("startRadio"); engine.startRadio(artistName: artistName) }
    func startRadioFromSong(_ song: Song) { count("startRadioFromSong"); engine.startRadioFromSong(song) }
    func startSongSimilarityMix(_ song: Song) {
        count("startSongSimilarityMix")
        engine.startSongSimilarityMix(song)
    }
    func playRadio(station: InternetRadioStation) { count("playRadio"); engine.playRadio(station: station) }
    func stopRadioMode() { count("stopRadioMode"); engine.stopRadioMode() }

    // MARK: - Processing

    var eqEnabled: Bool { engine.eqEnabled }
    var userVolume: Float {
        get { engine.userVolume }
        set { engine.userVolume = newValue }
    }
    var playbackRate: Float {
        get { engine.playbackRate }
        set { engine.playbackRate = newValue }
    }
    var visualizerActive: Bool {
        get { engine.visualizerActive }
        set { engine.visualizerActive = newValue }
    }
    var volume: Float {
        get { engine.volume }
        set { engine.volume = newValue }
    }
    func applyEQToggle(enabled: Bool) { count("applyEQToggle"); engine.applyEQToggle(enabled: enabled) }
    func applyEffectiveVolume() { count("applyEffectiveVolume"); engine.applyEffectiveVolume() }

    // MARK: - Predownload

    var predownloadStatus: PredownloadStatus { engine.predownloadStatus }
    var predownloadSpeed: Double { engine.predownloadSpeed }
    var predownloadsPending: Int { engine.predownloadsPending }
    func prepareLookahead() { count("prepareLookahead"); engine.prepareLookahead() }

    // MARK: - History

    var recentlyPlayed: [Song] { engine.recentlyPlayed }
    func addRandomSongPlayed(songId: String) {
        count("addRandomSongPlayed")
        engine.addRandomSongPlayed(songId: songId)
    }
    func restorePlayQueue(client: SubsonicClient) {
        count("restorePlayQueue")
        engine.restorePlayQueue(client: client)
    }

    // MARK: - Lifecycle persistence

    func savePlayQueue(client: SubsonicClient) {
        count("savePlayQueue")
        engine.savePlayQueue(client: client)
    }
    func saveQueueLocally() { count("saveQueueLocally"); engine.saveQueueLocally() }
    func createBookmarkIfNeeded(client: SubsonicClient) {
        count("createBookmarkIfNeeded")
        engine.createBookmarkIfNeeded(client: client)
    }
    func refreshPlaybackState() { count("refreshPlaybackState"); engine.refreshPlaybackState() }
}

/// The application's single composition point for playback.
///
/// One instance for the process lifetime, so a SwiftUI scene or view rebuilding cannot produce a
/// second façade — and, more importantly, cannot produce a second set of observers, remote-command
/// registrations, Now Playing writers or scrobble reporters. None of those live here today (they
/// remain inside `AudioEngine`), and this is where a future selector will be installed rather than
/// scattered across call sites.
///
/// Resolves to: `ApplicationPlaybackRouter` → `LegacyAudioEngineAdapter` → `AudioEngine.shared`.
///
/// **`shared` is one stable object for the process lifetime**, and that is the point of routing
/// through the router rather than swapping what `shared` returns. Eight surfaces captured this
/// property during Lane 2; if its identity could change under them the app would end up with two
/// queue authorities and no way to tell which one the user is looking at. The engine *decision*
/// lives inside the router; the object callers hold never changes.
///
/// The persistent PCM controller is **not** constructed here, and the router cannot select it.
@MainActor
enum ApplicationPlayback {
    /// Created once, lazily, on first use.
    static let shared: ApplicationPlaybackControlling = ApplicationPlaybackRouter()

    /// The router, for DEBUG diagnostics and the stable-authority tests.
    #if DEBUG
    static var router: ApplicationPlaybackRouter? { shared as? ApplicationPlaybackRouter }

    /// The legacy adapter behind the router, for tests that need the delegation counters. Reaches
    /// through the router rather than casting `shared`, which is no longer the adapter itself.
    /// Nil when a test has substituted a recorder for the legacy backend — the production router
    /// always holds the real adapter.
    static var legacyAdapter: LegacyAudioEngineAdapter? {
        router?.legacyAdapterForTesting as? LegacyAudioEngineAdapter
    }
    #endif
}
