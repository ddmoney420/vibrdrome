import Foundation
import os.log

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

    /// Every routing decision, logged. Closed enums and generation numbers only — never a song
    /// title, URL or credential — so a device log answers "which backend took generation N and
    /// why" without reconstruction. Added after an acceptance run spent an evening reverse-
    /// engineering exactly that from screenshots.
    private let routingLog = Logger(subsystem: "com.vibrdrome.app", category: "PlaybackRouting")

    /// The legacy backend. Typed as the application contract rather than the concrete adapter so a
    /// routing test can substitute a recorder for the one step that would otherwise open a real
    /// `AVQueuePlayer` against a real server; production always gets `LegacyAudioEngineAdapter`.
    private let legacy: any ApplicationPlaybackControlling

    /// The backend that owns the current session, derived from ownership rather than stored.
    ///
    /// Derived on purpose: a stored copy could disagree with `ownership.authority`, and "which
    /// engine does the UI think is playing" disagreeing with "which engine is playing" is exactly
    /// the two-authority failure this lane exists to prevent.
    var selectedBackend: PlaybackBackend {
        ownership.authority == .persistent ? .persistent : .legacy
    }

    /// Builds the persistent stack when — and only when — preparation is explicitly requested.
    private let persistentBuilder: any PersistentPlaybackAssemblyBuilding

    /// The persistent stack, once built. Retained for the process lifetime so a second preparation
    /// cannot produce a second engine, graph or pool.
    private(set) var persistentAssembly: PersistentPlaybackAssembly?

    /// How far persistent construction has got. Cold launch is always `.notConstructed` — nothing
    /// in app init, router init, view construction, diagnostics, remote-command setup, CarPlay,
    /// Watch, App Intents, scene activation, restoration or policy evaluation builds it.
    private(set) var persistentPreparationState: PersistentPreparationState = .notConstructed

    /// How far selection has got for the current playback session.
    private(set) var sessionSelectionState: PlaybackSessionSelectionState = .idle

    /// Single source of truth for which backend may own audio, the session, Now Playing, scrobble
    /// credit and the visualizer feed.
    let ownership = PlaybackOwnershipCoordinator()

    // MARK: - Planning generations

    /// The newest explicit playback request. Every session start takes the next value, so a plan
    /// that finishes preparing after the user has moved on can be recognised and dropped.
    private(set) var pendingPlanningGeneration: UInt64 = 0
    /// The newest generation that actually reached the executor.
    private(set) var lastCompletedPlanningGeneration: UInt64 = 0
    /// True from the moment a new session begins replacing the current one until its plan has been
    /// executed or dropped.
    private(set) var isReplacingSession = false

    /// The selection in flight, cancelled by the next request.
    private var planningTask: Task<Void, Never>?
    /// The persistent side of the current session, built at most once per process.
    private var persistentPort: (any PersistentPlaybackSessionPort)?
    private var planExecutor: PlaybackSessionPlanExecutor?

    init(
        legacy: any ApplicationPlaybackControlling = LegacyAudioEngineAdapter(),
        persistentBuilder: any PersistentPlaybackAssemblyBuilding
            = ProductionPersistentPlaybackAssemblyBuilder()
    ) {
        self.legacy = legacy
        self.persistentBuilder = persistentBuilder
    }

    #if DEBUG
    /// Test seam: substitutes the persistent side, so a routing test can prove where commands land
    /// without building an audio graph. Ignored once a session has been started.
    var persistentPortOverrideForTesting: (any PersistentPlaybackSessionPort)?
    /// Test seam: substitutes the finalized plan, for tests about *routing* rather than about
    /// planning. Tests that are about planning leave this nil and supply real prepared media.
    var planOverrideForTesting:
        ((PlaybackSessionSelectionRequest) async -> PlaybackSessionSelectionPlan)?

    /// Waits for the selection in flight, so a test can assert on a settled session rather than
    /// polling. Returns immediately when nothing is planning.
    func awaitPendingSelectionForTesting() async {
        await planningTask?.value
    }

    /// End the current session and release everything it holds.
    ///
    /// The teardown a routing test owes the next suite: no selection in flight, no authority
    /// granted, no persistent transport running, no audible callback installed, and the persistent
    /// backend back in a startable state. Awaits the port's teardown, so on return the persistent
    /// side is genuinely clean rather than merely told to clean up.
    func releaseSessionForTesting() async {
        supersedePendingSelection()
        if let port = persistentPort {
            await port.tearDown()
            port.clearAudibleObserver()
        }
        ownership.release()
        isReplacingSession = false
        sessionSelectionState = .idle
        planOverrideForTesting = nil
    }
    #endif

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

    /// Everything that is **not** owned by the session: radio, predownload, history, lifecycle
    /// persistence, and the state projections the persistent backend cannot answer yet.
    ///
    /// These are shared services rather than transport, so they stay on the legacy engine whichever
    /// backend owns audio. Routing them by authority would either duplicate them or make them
    /// unavailable during a persistent session.
    private var routed: any ApplicationPlaybackControlling { legacy }

    /// The persistent transport, but **only while it holds authority**.
    ///
    /// Returning nil whenever authority is anything else is what makes "zero inactive-backend
    /// operations" structural rather than a rule to remember: there is no way to reach the
    /// persistent transport when it does not own the session.
    private var activePersistent: (any PersistentTransportRouting)? {
        ownership.authority == .persistent ? persistentPort?.transport : nil
    }

    /// Send one operation to the backend holding authority, and to nothing else.
    private func onActiveBackend(
        persistent: (any PersistentTransportRouting) -> Void,
        legacy legacyOperation: (any ApplicationPlaybackControlling) -> Void
    ) {
        if let active = activePersistent { persistent(active) } else { legacyOperation(legacy) }
    }

    /// Whether persistent currently owns transport.
    var isPersistentSessionActive: Bool { ownership.authority == .persistent }

    #if DEBUG
    /// The legacy backend, for tests that need its delegation counters. DEBUG-only, and it is the
    /// adapter — never `AudioEngine` and never `AVQueuePlayer`.
    var legacyAdapterForTesting: any ApplicationPlaybackControlling { legacy }
    #endif

    // MARK: - Starting a session

    /// Begin a new explicit finite-track session.
    ///
    /// **What makes this the one planning entry point.** Every production `play(...)` form resolves
    /// here: the protocol has a single `play(song:from:at:)` requirement and the convenience
    /// overload delegates to it, so there is exactly one place where a new session is decided. Next,
    /// Previous, Resume and Toggle are deliberately *not* here — they continue the session that
    /// already exists, and re-planning on each of them would re-materialize the source and could
    /// move the backend under audible audio.
    ///
    /// `startOffsetSeconds` exists because a session can in principle begin mid-track; production
    /// callers always pass zero. A non-zero offset routes to legacy — the persistent engine has no
    /// resume-from-offset path, and starting it at zero instead would play the wrong audio.
    func beginSession(songs: [Song], startIndex: Int, startOffsetSeconds: TimeInterval = 0) {
        let generation = supersedePendingSelection()
        guard let first = songs.indices.contains(startIndex) ? songs[startIndex] : songs.first else {
            sessionSelectionState = .failed(reason: .emptySession)
            return
        }

        // Flag Off, Release, or a mid-track start: no planner, no persistent construction, one
        // legacy start. Authority is left alone so a build that never enables the flag behaves as
        // it did before this lane. When a persistent session IS active, its teardown must complete
        // before legacy starts — that replacement runs as this request's ordered transition,
        // fenced by the same planning generation as any other session start.
        guard PersistentRoutingSetting.isEnabled, startOffsetSeconds <= 0 else {
            let reason: PlaybackBackendDecisionReason = startOffsetSeconds > 0
                ? .requiredMediaPropertiesUnknown : .supportedLocalSource
            // `grantsAuthority: false` preserves the flag-off contract: authority is left alone so
            // a build that never enables the flag behaves as it did before this lane.
            beginLegacyReplacement(reason: reason, generation: generation,
                                   grantsAuthority: false) {
                $0.play(song: first, from: songs, at: startIndex)
            }
            return
        }

        let request = PlaybackSessionSelectionRequest(
            songs: songs, startIndex: startIndex, startOffsetSeconds: startOffsetSeconds,
            contentKind: .finiteTrack, generation: generation)
        sessionSelectionState = .evaluating
        isReplacingSession = true
        planningTask = Task { [weak self] in
            guard let self else { return }
            let plan = await self.plan(for: request)
            // Stale rejection is a generation comparison, and a dropped plan releases its prepared
            // source so it can never be adopted after the queue has moved on.
            guard !Task.isCancelled, request.generation == self.pendingPlanningGeneration else {
                self.drop(plan)
                return
            }
            await self.executePlan(plan, for: request)
        }
    }

    private func plan(for request: PlaybackSessionSelectionRequest)
        async -> PlaybackSessionSelectionPlan {
        #if DEBUG
        if let override = planOverrideForTesting { return await override(request) }
        #endif
        sessionSelectionState = .preparing
        let planner = PlaybackSessionSelectionPlanner(
            prepareAssembly: { [weak self] in
                guard let self else { throw PersistentPreparationFailure.builderRefused }
                return try self.preparePersistentBackend()
            })
        return await planner.plan(request: request)
    }

    private func executePlan(_ plan: PlaybackSessionSelectionPlan,
                             for request: PlaybackSessionSelectionRequest) async {
        // Persistent → anything is a replacement, and the old session must let go *before* the new
        // one is executed: the executor's handoff quiesces legacy, not persistent, so leaving the
        // old persistent session holding authority would put two engines on the same graph. The
        // await is the point — the old domain is clean before the new source is adopted.
        await releasePersistentIfActive()

        let outcome = await executor(for: plan).execute(
            plan: plan, request: request, currentGeneration: pendingPlanningGeneration)
        lastCompletedPlanningGeneration = request.generation
        isReplacingSession = false
        sessionSelectionState = Self.selectionState(for: plan, outcome: outcome)
        routingLog.info("""
            generation \(request.generation, privacy: .public): plan \
            \(plan.describedForDiagnostics, privacy: .public) -> \
            \(outcome.describedForDiagnostics, privacy: .public)
            """)
    }

    /// Start a session that is legacy by definition — radio and live streams, which the persistent
    /// engine cannot schedule because they have no finite timeline.
    private func beginLegacyOnlySession(reason: PlaybackBackendDecisionReason,
                                        _ operation: @escaping @MainActor
                                            (any ApplicationPlaybackControlling) -> Void) {
        let generation = supersedePendingSelection()
        beginLegacyReplacement(reason: reason, generation: generation, grantsAuthority: true,
                               operation)
    }

    /// The one legacy-start path for synchronous entry points, honest about persistent teardown.
    ///
    /// No persistent session active: exactly today's behaviour — record, start (and for the paths
    /// that own authority, grant it), all synchronously. A persistent session active: the request
    /// becomes this generation's ordered transition — persistent teardown is awaited to completion,
    /// the generation re-checked (a newer request wins and this one starts nothing), and only then
    /// does legacy start. The transition lives in `planningTask`, so the next request supersedes it
    /// exactly like a planned selection.
    private func beginLegacyReplacement(reason: PlaybackBackendDecisionReason,
                                        generation: UInt64,
                                        grantsAuthority: Bool,
                                        _ operation: @escaping @MainActor
                                            (any ApplicationPlaybackControlling) -> Void) {
        guard ownership.authority == .persistent, persistentPort != nil else {
            if grantsAuthority { ownership.grant(.legacy) }
            sessionSelectionState = .legacy(reason: reason)
            lastCompletedPlanningGeneration = generation
            routingLog.info("""
                generation \(generation, privacy: .public): legacy-only start \
                (\(reason.rawValue, privacy: .public))
                """)
            operation(legacy)
            return
        }
        isReplacingSession = true
        planningTask = Task { [weak self] in
            guard let self else { return }
            // Teardown always completes — a half-released persistent session is worse than a
            // released one whatever happened to the request — but authority and the start belong
            // only to the newest request.
            await self.releasePersistentIfActive()
            guard generation == self.pendingPlanningGeneration else {
                self.routingLog.info("""
                    generation \(generation, privacy: .public): legacy replacement superseded \
                    after persistent teardown
                    """)
                return
            }
            if grantsAuthority { self.ownership.grant(.legacy) }
            self.sessionSelectionState = .legacy(reason: reason)
            self.lastCompletedPlanningGeneration = generation
            self.isReplacingSession = false
            self.routingLog.info("""
                generation \(generation, privacy: .public): legacy-only start replaced a \
                persistent session (\(reason.rawValue, privacy: .public))
                """)
            operation(self.legacy)
        }
    }

    /// Take the next planning generation and invalidate whatever was in flight.
    @discardableResult
    private func supersedePendingSelection() -> UInt64 {
        planningTask?.cancel()
        planningTask = nil
        pendingPlanningGeneration += 1
        return pendingPlanningGeneration
    }

    /// Release a persistent session so another backend can own audio.
    ///
    /// Ordered exactly like the executor's fallback, and for the same reason: the transport goes
    /// first — and its teardown is **awaited to completion**, so the node is stopped, the pool
    /// reclaimed and the sources closed before anything else happens — then the callback is cleared
    /// so a boundary from the dead session cannot latch against the next one, and authority is
    /// revoked before anything else is granted.
    private func releasePersistentIfActive() async {
        guard ownership.authority == .persistent, let port = persistentPort else { return }
        await port.tearDown()
        port.clearAudibleObserver()
        ownership.release()
    }

    /// A plan that will not be executed must not stay adoptable.
    private func drop(_ plan: PlaybackSessionSelectionPlan) {
        if case .persistent(let source, _) = plan { source.release() }
        isReplacingSession = false
        sessionSelectionState = .idle
    }

    /// The executor for a plan.
    ///
    /// A legacy plan is executed with an inert persistent side rather than a real one: the
    /// executor's legacy path never touches it, and building one would construct an engine, a graph
    /// and a pool for a session that will never use them.
    private func executor(for plan: PlaybackSessionSelectionPlan) -> PlaybackSessionPlanExecutor {
        if let existing = planExecutor { return existing }
        guard plan.plannedBackend == .persistent, let port = makePersistentPort() else {
            return PlaybackSessionPlanExecutor(legacy: legacyPort(),
                                               persistent: InertPersistentSessionPort(),
                                               ownership: ownership)
        }
        persistentPort = port
        let created = PlaybackSessionPlanExecutor(legacy: legacyPort(), persistent: port,
                                                  ownership: ownership)
        planExecutor = created
        return created
    }

    private func legacyPort() -> AudioEngineLegacySessionPort {
        AudioEngineLegacySessionPort(transport: legacy)
    }

    /// The persistent side, built at most once so a second session cannot produce a second engine.
    private func makePersistentPort() -> (any PersistentPlaybackSessionPort)? {
        if let existing = persistentPort { return existing }
        #if DEBUG
        if let override = persistentPortOverrideForTesting { return override }
        #endif
        // Reached only from a persistent plan, which the planner produces only after the assembly
        // has already been built to materialize and inspect the source — so this returns the
        // assembly that decision was made against rather than constructing a second one.
        guard let assembly = try? preparePersistentBackend() else { return nil }
        return PersistentAssemblySessionPort(assembly: assembly)
    }

    private static func selectionState(for plan: PlaybackSessionSelectionPlan,
                                       outcome: PlaybackSessionExecutionOutcome)
        -> PlaybackSessionSelectionState {
        switch outcome {
        case .started(.persistent):
            .persistent(reason: plan.decision?.reason ?? .supportedLocalSource)
        case .started(.legacy):
            if case .legacy(let reason) = plan { .legacy(reason: reason) } else { .legacy(reason: .supportedLocalSource) }
        case .fellBackToLegacy(let reason): .failed(reason: reason)
        case .persistentRetained: .persistent(reason: plan.decision?.reason ?? .supportedLocalSource)
        case .refused(let reason): .failed(reason: reason)
        case .superseded: .idle
        }
    }

    // MARK: - Diagnostics

    /// What the router is actually doing. Reports the truth, including that the persistent
    /// controller is not constructed — an installed build must never claim otherwise.
    struct Diagnostics: Equatable, Sendable {
        var routerActive: Bool
        var selectedBackend: PlaybackBackend
        var legacyAdapterActive: Bool
        var persistentControllerConstructed: Bool
        var persistentPreparationState: PersistentPreparationState
        var pendingPlanningGeneration: UInt64
        var lastCompletedPlanningGeneration: UInt64
        var authority: PlaybackAuthority
        var isReplacingSession: Bool
        var audibleBoundaryReached: Bool
        var isFallbackPermitted: Bool
        var selectionState: String
        var heartbeat: PersistentHeartbeatDiagnostics

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
            Active transport backend: \(selectedBackend == .legacy ? "Legacy" : "Persistent")
            Playback authority: \(authority.rawValue)
            Selection state: \(selectionState)
            Planning generation: \(lastCompletedPlanningGeneration) completed \
            of \(pendingPlanningGeneration) requested
            Session replacement in progress: \(isReplacingSession ? "Yes" : "No")
            Persistent audible boundary reached: \(audibleBoundaryReached ? "Yes" : "No")
            Fallback permitted: \(isFallbackPermitted ? "Yes" : "No")
            Legacy adapter: \(legacyAdapterActive ? "Active" : "Inactive")
            Persistent controller: \(persistentControllerConstructed ? "Constructed" : "Not constructed")
            \(heartbeat.summary)
            Now Playing ownership: Active (persistent publishes at render-observed boundaries)
            Scrobble / visualizer ownership: Pending (legacy suppressed during persistent transport)
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
            persistentPreparationState: persistentPreparationState,
            pendingPlanningGeneration: pendingPlanningGeneration,
            lastCompletedPlanningGeneration: lastCompletedPlanningGeneration,
            authority: ownership.authority,
            isReplacingSession: isReplacingSession,
            audibleBoundaryReached: ownership.audibleBoundaryReached,
            isFallbackPermitted: ownership.isFallbackPermitted,
            selectionState: sessionSelectionState.describedForDiagnostics,
            // Read from the port rather than from the active-transport accessor: a heartbeat that
            // outlived its session would be invisible if it could only be seen while that session
            // still held authority, and that is exactly the failure worth surfacing.
            heartbeat: persistentPort?.transport.heartbeatDiagnostics
                ?? PersistentHeartbeatDiagnostics()
        )
    }

    // MARK: - Transport

    /// The one entry point that begins a new session, and therefore the one that plans.
    func play(song: Song, from queue: [Song]?, at index: Int) {
        beginSession(songs: queue ?? [song], startIndex: index)
    }

    // Everything below continues the session that already exists, so none of it plans — it goes to
    // whichever backend holds authority, and to nothing else.

    func pause() { onActiveBackend(persistent: { $0.pause() }, legacy: { $0.pause() }) }
    func resume() { onActiveBackend(persistent: { $0.resume() }, legacy: { $0.resume() }) }
    func stop() { onActiveBackend(persistent: { $0.stop() }, legacy: { $0.stop() }) }
    func togglePlayPause() {
        onActiveBackend(persistent: { $0.togglePlayPause() }, legacy: { $0.togglePlayPause() })
    }
    func next() { onActiveBackend(persistent: { $0.next() }, legacy: { $0.next() }) }
    func previous() { onActiveBackend(persistent: { $0.previous() }, legacy: { $0.previous() }) }
    func seek(to time: TimeInterval) {
        onActiveBackend(persistent: { $0.seek(to: time) }, legacy: { $0.seek(to: time) })
    }
    func skipToIndex(_ index: Int) {
        onActiveBackend(persistent: { $0.skipToIndex(index) }, legacy: { $0.skipToIndex(index) })
    }

    // MARK: - Queue

    func addToQueue(_ song: Song) {
        onActiveBackend(persistent: { $0.addToQueue(song) }, legacy: { $0.addToQueue(song) })
    }
    func addToQueue(_ songs: [Song]) {
        onActiveBackend(persistent: { adapter in songs.forEach { adapter.addToQueue($0) } },
                        legacy: { $0.addToQueue(songs) })
    }
    func addToQueueNext(_ song: Song) {
        onActiveBackend(persistent: { $0.addToQueueNext(song) },
                        legacy: { $0.addToQueueNext(song) })
    }
    func addToQueueNext(_ songs: [Song]) {
        onActiveBackend(persistent: { adapter in songs.reversed().forEach { adapter.addToQueueNext($0) } },
                        legacy: { $0.addToQueueNext(songs) })
    }
    /// Starred and rating are library metadata rather than transport: they update the queue's
    /// presentation on the shared engine whichever backend is playing.
    func updateQueueSongStarred(id: String, starred: Bool) {
        routed.updateQueueSongStarred(id: id, starred: starred)
    }
    func updateQueueSongRating(id: String, rating: Int?) {
        routed.updateQueueSongRating(id: id, rating: rating)
    }
    func clearQueue() {
        onActiveBackend(persistent: { $0.clearQueue() }, legacy: { $0.clearQueue() })
    }
    func removeFromQueue(atAbsolute index: Int) {
        onActiveBackend(persistent: { $0.removeFromQueue(atAbsolute: index) },
                        legacy: { $0.removeFromQueue(atAbsolute: index) })
    }
    func moveInUpNext(from source: IndexSet, to destination: Int) {
        onActiveBackend(persistent: { $0.moveInUpNext(from: source, to: destination) },
                        legacy: { $0.moveInUpNext(from: source, to: destination) })
    }

    // MARK: - State
    //
    // Every one of these is a computed read-through. Nothing is stored, mirrored or cached, so the
    // extra layer cannot become a second source of truth — and SwiftUI Observation still registers
    // against the `@Observable` engine, because the read happens inside the caller's tracking scope.

    // State the active backend genuinely answers is read from it. Answering these from a quiesced
    // legacy engine during a persistent session would not be a missing feature, it would be wrong:
    // it holds no items, so it reports stopped at position zero while audio is playing.
    var isPlaying: Bool { activePersistent?.isPlaying ?? routed.isPlaying }
    var currentSong: Song? { activePersistent?.currentSong ?? routed.currentSong }
    var currentTime: TimeInterval { activePersistent?.currentTime ?? routed.currentTime }
    var smoothCurrentTime: TimeInterval { activePersistent?.currentTime ?? routed.smoothCurrentTime }
    // Buffering stays a legacy concept: the persistent engine schedules decoded PCM ahead of the
    // boundary, and its "not ready" state is a controlled wait, not a buffering spinner. During a
    // persistent session the honest answer is false — reading the quiesced legacy engine here
    // would report the stale session it was handed over from.
    var isBuffering: Bool { activePersistent != nil ? false : routed.isBuffering }
    // Durations follow authority like the queue does: a quiesced legacy engine answers with a
    // days-old track's duration, which is how the full player showed 0:00 remaining early while
    // persistent audio played on (proven by device export, 2026-08-29).
    var duration: TimeInterval { activePersistent?.duration ?? routed.duration }
    var effectiveDuration: TimeInterval {
        activePersistent?.effectiveDuration ?? routed.effectiveDuration
    }

    // The queue and every projection derived from it come from ONE backend. Splitting them is not a
    // cosmetic inconsistency: `nextSongIndex()` resolved against legacy and used to subscript a
    // persistent `queue` is an out-of-range crash, which is what it did in the mini player.
    var queue: [Song] { activePersistent?.queue ?? routed.queue }
    var currentIndex: Int { activePersistent?.currentIndex ?? routed.currentIndex }
    var upNextEntries: [(index: Int, song: Song)] {
        activePersistent?.upNextEntries ?? routed.upNextEntries
    }
    var upNext: [Song] { activePersistent?.upNext ?? routed.upNext }
    func nextSongIndex() -> Int? { activePersistent?.nextSongIndex() ?? routed.nextSongIndex() }
    var playingFromContext: String? {
        get { routed.playingFromContext }
        set { routed.playingFromContext = newValue }
    }

    // MARK: - Repeat and shuffle

    var shuffleEnabled: Bool { activePersistent?.shuffleEnabled ?? routed.shuffleEnabled }
    var repeatMode: RepeatMode { activePersistent?.repeatMode ?? routed.repeatMode }
    func toggleShuffle() {
        onActiveBackend(persistent: { $0.setShuffleEnabled(!$0.shuffleEnabled) },
                        legacy: { $0.toggleShuffle() })
    }
    func cycleRepeatMode() {
        onActiveBackend(persistent: { $0.setRepeatMode($0.repeatMode.next) },
                        legacy: { $0.cycleRepeatMode() })
    }

    // MARK: - Radio

    // Radio has no finite timeline, so the persistent engine cannot schedule it. Starting one is
    // always a new **legacy** session, which means releasing persistent first rather than leaving
    // two backends believing they own audio.

    var isRadioMode: Bool { routed.isRadioMode }
    var currentRadioStation: InternetRadioStation? { routed.currentRadioStation }
    var radioSeedArtistName: String? { routed.radioSeedArtistName }
    func startRadio(artistName: String) {
        beginLegacyOnlySession(reason: .radioContent) { $0.startRadio(artistName: artistName) }
    }
    func startRadioFromSong(_ song: Song) {
        beginLegacyOnlySession(reason: .radioContent) { $0.startRadioFromSong(song) }
    }
    func startSongSimilarityMix(_ song: Song) {
        beginLegacyOnlySession(reason: .radioContent) { $0.startSongSimilarityMix(song) }
    }
    func playRadio(station: InternetRadioStation) {
        beginLegacyOnlySession(reason: .liveStreamContent) { $0.playRadio(station: station) }
    }
    func stopRadioMode() { routed.stopRadioMode() }

    // MARK: - Processing

    var eqEnabled: Bool { activePersistent?.eqEnabled ?? routed.eqEnabled }
    var volume: Float {
        get { activePersistent?.volume ?? routed.volume }
        set { onActiveBackend(persistent: { $0.volume = newValue }, legacy: { $0.volume = newValue }) }
    }
    var userVolume: Float {
        get { activePersistent?.userVolume ?? routed.userVolume }
        set {
            onActiveBackend(persistent: { $0.userVolume = newValue },
                            legacy: { $0.userVolume = newValue })
        }
    }
    var playbackRate: Float {
        get { routed.playbackRate }
        set { routed.playbackRate = newValue }
    }
    var visualizerActive: Bool {
        get { routed.visualizerActive }
        set { routed.visualizerActive = newValue }
    }
    func applyEQToggle(enabled: Bool) {
        onActiveBackend(persistent: { $0.applyEQToggle(enabled: enabled) },
                        legacy: { $0.applyEQToggle(enabled: enabled) })
    }
    func applyEffectiveVolume() {
        onActiveBackend(persistent: { $0.applyEffectiveVolume() },
                        legacy: { $0.applyEffectiveVolume() })
    }

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
