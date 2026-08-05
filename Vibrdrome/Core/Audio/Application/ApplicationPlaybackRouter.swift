import Foundation

/// Which playback implementation the application is routed to.
///
/// `.persistent` exists so the routing decision has a name before it has a second destination.
/// **Nothing in Lane 3A can select it**: `ApplicationPlaybackRouter.selectedBackend` is
/// `private(set)` and never assigned, so `.legacy` is the only reachable runtime value.
enum PlaybackBackend: String, Equatable, Sendable, CaseIterable {
    case legacy
    case persistent
}

/// The application's stable playback authority.
///
/// **Why a router at all, when it currently routes one way.** Lane 2 moved 170 call sites across
/// eight surfaces onto `ApplicationPlayback.shared`. The engine selection those lanes were building
/// toward needs somewhere to live, and the one thing it must not become is a `shared` that hands
/// back different objects at different times: SwiftUI views, CarPlay, the Watch, Siri, remote
/// commands and the scene lifecycle all captured `ApplicationPlayback.shared`, and if that identity
/// could change under them the app would end up with two queue authorities and no way to tell which
/// one the user is looking at.
///
/// So the authority is **stable for the process lifetime** and the *decision* lives inside it. A
/// future lane changes what `routed` returns; it never changes what callers hold.
///
/// Lane 3A adds the layer and nothing else. Every member below forwards to the legacy adapter, so
/// behaviour is identical to calling it directly — by construction, not by assertion.
@MainActor
final class ApplicationPlaybackRouter: ApplicationPlaybackControlling {

    /// The only implementation that exists today. Held concretely so DEBUG diagnostics and the
    /// delegation counters remain reachable without widening the production surface.
    private let legacy: LegacyAudioEngineAdapter

    /// The current routing decision. Fixed at `.legacy` for the whole process in Lane 3A — there is
    /// no setter, and no source-format or capability predicate exists yet. That predicate is Lane 3B;
    /// constructing the persistent controller is Lane 3C; selecting it is Lane 3D.
    private(set) var selectedBackend: PlaybackBackend = .legacy

    /// Builds the persistent stack when — and only when — preparation is explicitly requested.
    private let persistentBuilder: any PersistentPlaybackAssemblyBuilding

    /// The persistent stack, once built. Retained for the process lifetime so a second preparation
    /// cannot produce a second engine, graph or pool.
    private(set) var persistentAssembly: PersistentPlaybackAssembly?

    /// How far persistent construction has got. Cold launch is always `.notConstructed` — nothing
    /// in app init, router init, view construction, diagnostics, remote-command setup, CarPlay,
    /// Watch, App Intents, scene activation, restoration or policy evaluation builds it.
    private(set) var persistentPreparationState: PersistentPreparationState = .notConstructed

    init(
        legacy: LegacyAudioEngineAdapter = LegacyAudioEngineAdapter(),
        persistentBuilder: any PersistentPlaybackAssemblyBuilding
            = ProductionPersistentPlaybackAssemblyBuilder()
    ) {
        self.legacy = legacy
        self.persistentBuilder = persistentBuilder
    }

    // MARK: - Persistent preparation

    /// Construct the persistent stack once, and keep it.
    ///
    /// **Explicit by design.** No playback operation triggers this — not even Play. Lane 3C exists
    /// to measure what construction costs and to prove the result is inert, so construction has to
    /// be something a person asks for, not a side effect of using the app.
    ///
    /// Idempotent: a second call returns the same assembly. Never changes `selectedBackend`, never
    /// starts playback, never touches the queue, never publishes Now Playing, never registers a
    /// remote command. A failure leaves legacy fully authoritative.
    @discardableResult
    func preparePersistentBackend() throws -> PersistentPlaybackAssembly {
        if let existing = persistentAssembly {
            persistentPreparationState = .ready
            return existing
        }
        persistentPreparationState = .constructing
        do {
            let assembly = try persistentBuilder.build()
            persistentAssembly = assembly
            persistentPreparationState = .ready
            return assembly
        } catch let failure as PersistentPreparationFailure {
            // No partial assembly is retained: `persistentAssembly` is only assigned on success.
            persistentPreparationState = .failed(failure)
            throw failure
        } catch {
            persistentPreparationState = .failed(.builderRefused)
            throw PersistentPreparationFailure.builderRefused
        }
    }

    /// The destination for the current decision.
    ///
    /// Deliberately a `switch` on the decision rather than an identity check on a stored controller:
    /// the policy has to be readable as policy, and a future lane must not be able to change routing
    /// by accidentally reassigning an object reference.
    private var routed: any ApplicationPlaybackControlling {
        switch selectedBackend {
        case .legacy:
            return legacy
        case .persistent:
            // Unreachable: nothing can select `.persistent` yet. Trapping in DEBUG makes a premature
            // selection loud during development, while release falls back to the only implementation
            // that exists rather than playing through something unbuilt.
            assertionFailure("persistent backend selected before it is constructed (Lane 3C/3D)")
            return legacy
        }
    }

    #if DEBUG
    /// The legacy adapter, for tests that need its delegation counters. DEBUG-only, and it is the
    /// adapter — never `AudioEngine` and never `AVQueuePlayer`.
    var legacyAdapterForTesting: LegacyAudioEngineAdapter { legacy }
    #endif

    // MARK: - Diagnostics

    /// What the router is actually doing. Reports the truth, including that the persistent
    /// controller is not constructed — an installed build must never claim otherwise.
    struct Diagnostics: Equatable, Sendable {
        var routerActive: Bool
        var selectedBackend: PlaybackBackend
        var legacyAdapterActive: Bool
        var persistentControllerConstructed: Bool
        var persistentPreparationState: PersistentPreparationState

        var preparationDescription: String {
            switch persistentPreparationState {
            case .notConstructed: "Not constructed"
            case .constructing: "Constructing"
            case .ready: "Ready"
            case .failed(let failure): "Failed (\(failure.rawValue))"
            }
        }

        var summary: String {
            """
            Application playback router: \(routerActive ? "Active" : "Inactive")
            Persistent preparation: \(preparationDescription)
            Selected backend: \(selectedBackend == .legacy ? "Legacy" : "Persistent")
            Legacy adapter: \(legacyAdapterActive ? "Active" : "Inactive")
            Persistent controller: \(persistentControllerConstructed ? "Constructed" : "Not constructed")
            Persistent engine selected: \(selectedBackend == .persistent ? "Yes" : "No")
            """
        }
    }

    var diagnostics: Diagnostics {
        Diagnostics(
            routerActive: true,
            selectedBackend: selectedBackend,
            legacyAdapterActive: true,
            // Read, never asserted: if anything ever does construct a persistent controller, this
            // must say so rather than keep reporting the comfortable answer.
            persistentControllerConstructed: GaplessDiagnosticsRegistry.current != nil,
            persistentPreparationState: persistentPreparationState
        )
    }

    // MARK: - Transport

    func play(song: Song, from queue: [Song]?, at index: Int) {
        routed.play(song: song, from: queue, at: index)
    }
    func pause() { routed.pause() }
    func resume() { routed.resume() }
    func stop() { routed.stop() }
    func togglePlayPause() { routed.togglePlayPause() }
    func next() { routed.next() }
    func previous() { routed.previous() }
    func seek(to time: TimeInterval) { routed.seek(to: time) }
    func skipToIndex(_ index: Int) { routed.skipToIndex(index) }

    // MARK: - Queue

    func addToQueue(_ song: Song) { routed.addToQueue(song) }
    func addToQueue(_ songs: [Song]) { routed.addToQueue(songs) }
    func addToQueueNext(_ song: Song) { routed.addToQueueNext(song) }
    func addToQueueNext(_ songs: [Song]) { routed.addToQueueNext(songs) }
    func updateQueueSongStarred(id: String, starred: Bool) {
        routed.updateQueueSongStarred(id: id, starred: starred)
    }
    func updateQueueSongRating(id: String, rating: Int?) {
        routed.updateQueueSongRating(id: id, rating: rating)
    }
    func clearQueue() { routed.clearQueue() }
    func removeFromQueue(atAbsolute index: Int) { routed.removeFromQueue(atAbsolute: index) }
    func moveInUpNext(from source: IndexSet, to destination: Int) {
        routed.moveInUpNext(from: source, to: destination)
    }

    // MARK: - State
    //
    // Every one of these is a computed read-through. Nothing is stored, mirrored or cached, so the
    // extra layer cannot become a second source of truth — and SwiftUI Observation still registers
    // against the `@Observable` engine, because the read happens inside the caller's tracking scope.

    var isPlaying: Bool { routed.isPlaying }
    var currentSong: Song? { routed.currentSong }
    var currentTime: TimeInterval { routed.currentTime }
    var smoothCurrentTime: TimeInterval { routed.smoothCurrentTime }
    var isBuffering: Bool { routed.isBuffering }
    var duration: TimeInterval { routed.duration }
    var effectiveDuration: TimeInterval { routed.effectiveDuration }
    var queue: [Song] { routed.queue }
    var currentIndex: Int { routed.currentIndex }
    var upNextEntries: [(index: Int, song: Song)] { routed.upNextEntries }
    var upNext: [Song] { routed.upNext }
    func nextSongIndex() -> Int? { routed.nextSongIndex() }
    var playingFromContext: String? {
        get { routed.playingFromContext }
        set { routed.playingFromContext = newValue }
    }

    // MARK: - Repeat and shuffle

    var shuffleEnabled: Bool { routed.shuffleEnabled }
    var repeatMode: RepeatMode { routed.repeatMode }
    func toggleShuffle() { routed.toggleShuffle() }
    func cycleRepeatMode() { routed.cycleRepeatMode() }

    // MARK: - Radio

    var isRadioMode: Bool { routed.isRadioMode }
    var currentRadioStation: InternetRadioStation? { routed.currentRadioStation }
    var radioSeedArtistName: String? { routed.radioSeedArtistName }
    func startRadio(artistName: String) { routed.startRadio(artistName: artistName) }
    func startRadioFromSong(_ song: Song) { routed.startRadioFromSong(song) }
    func startSongSimilarityMix(_ song: Song) { routed.startSongSimilarityMix(song) }
    func playRadio(station: InternetRadioStation) { routed.playRadio(station: station) }
    func stopRadioMode() { routed.stopRadioMode() }

    // MARK: - Processing

    var eqEnabled: Bool { routed.eqEnabled }
    var volume: Float {
        get { routed.volume }
        set { routed.volume = newValue }
    }
    var userVolume: Float {
        get { routed.userVolume }
        set { routed.userVolume = newValue }
    }
    var playbackRate: Float {
        get { routed.playbackRate }
        set { routed.playbackRate = newValue }
    }
    var visualizerActive: Bool {
        get { routed.visualizerActive }
        set { routed.visualizerActive = newValue }
    }
    func applyEQToggle(enabled: Bool) { routed.applyEQToggle(enabled: enabled) }
    func applyEffectiveVolume() { routed.applyEffectiveVolume() }

    // MARK: - Predownload

    var predownloadStatus: PredownloadStatus { routed.predownloadStatus }
    var predownloadSpeed: Double { routed.predownloadSpeed }
    var predownloadsPending: Int { routed.predownloadsPending }
    func prepareLookahead() { routed.prepareLookahead() }

    // MARK: - History

    var recentlyPlayed: [Song] { routed.recentlyPlayed }
    func addRandomSongPlayed(songId: String) { routed.addRandomSongPlayed(songId: songId) }
    func restorePlayQueue(client: SubsonicClient) { routed.restorePlayQueue(client: client) }

    // MARK: - Lifecycle persistence

    func savePlayQueue(client: SubsonicClient) { routed.savePlayQueue(client: client) }
    func saveQueueLocally() { routed.saveQueueLocally() }
    func createBookmarkIfNeeded(client: SubsonicClient) {
        routed.createBookmarkIfNeeded(client: client)
    }
    func refreshPlaybackState() { routed.refreshPlaybackState() }
}
