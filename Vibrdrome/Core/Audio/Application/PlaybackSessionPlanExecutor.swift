import AVFoundation
import Foundation

/// What executing a finalized plan actually did.
///
/// Deliberately reports the backend that **started**, not the one the plan named: a persistent plan
/// that fell back has to be distinguishable from a legacy plan, or a diagnostic readout would claim
/// a handoff succeeded when it was undone.
enum PlaybackSessionExecutionOutcome: Equatable, Sendable {
    /// The named backend took the session and was started exactly once.
    case started(PlaybackSessionBackend)
    /// Persistent could not be brought up **before anything was heard**, so legacy took the session
    /// back and was started from the preserved snapshot.
    case fellBackToLegacy(SafePlaybackRoutingFailure)
    /// Persistent failed after the audible boundary. Automatic fallback is prohibited there — a
    /// cutover mid-track is a worse outcome than an error — so persistent keeps the session.
    case persistentRetained(SafePlaybackRoutingFailure)
    /// A newer generation superseded this plan. Nothing was started and nothing was torn down.
    case superseded
    /// The plan could not be executed at all. Nothing was started, and whatever owned audio before
    /// still owns it.
    case refused(SafePlaybackRoutingFailure)

    /// The backend owning audio afterwards, if this execution settled one.
    var backend: PlaybackSessionBackend? {
        switch self {
        case .started(let backend): backend
        case .fellBackToLegacy: .legacy
        case .persistentRetained: .persistent
        case .superseded, .refused: nil
        }
    }

    /// A safe, closed description — never a URL, credential, header or path.
    var describedForDiagnostics: String {
        switch self {
        case .started(let backend): "Started \(backend.rawValue)"
        case .fellBackToLegacy(let reason): "Fell back to legacy (\(reason.rawValue))"
        case .persistentRetained(let reason): "Persistent retained (\(reason.rawValue))"
        case .superseded: "Superseded"
        case .refused(let reason): "Refused (\(reason.rawValue))"
        }
    }
}

// MARK: - Ports

/// The legacy side of a handoff, as the executor needs it.
///
/// A port rather than a direct `AudioEngine` reference because starting legacy means starting a
/// real `AVQueuePlayer` against a real server — the one step in this sequence that cannot be driven
/// in a unit test. Everything else (transport state, snapshot capture, quiescence) is the real
/// engine behind the production implementation.
@MainActor
protocol LegacyPlaybackSessionPort: AnyObject {
    /// What legacy transport is actually holding. The item counts are the evidence, not the
    /// playing flag.
    var transportState: LegacyTransportState { get }
    /// Capture the live session **before** teardown removes the record of position.
    func captureSnapshot(startOffsetSeconds: TimeInterval) -> PlaybackSessionSnapshot
    /// Release transport ownership without ending the logical session.
    func quiesceForPersistentSession()
    /// Take the logical session as legacy's own. Starts nothing.
    func adopt(_ snapshot: PlaybackSessionSnapshot)
    /// Begin playback. Exactly one transport start per execution.
    func start(_ snapshot: PlaybackSessionSnapshot)
}

/// What the router sends to the persistent backend while it holds authority.
///
/// Separate from the handoff port because these are different jobs with different lifetimes: the
/// handoff port moves ownership once, and this carries every transport command for as long as that
/// ownership lasts. Keeping them apart is also what lets the executor's tests double a handoff
/// without implementing a transport surface they never exercise.
@MainActor
protocol PersistentTransportRouting: AnyObject {
    func play(song: Song, from newQueue: [Song]?, at index: Int)
    func pause()
    func resume()
    func stop()
    func togglePlayPause()
    func next()
    func previous()
    func seek(to time: TimeInterval)
    func skipToIndex(_ index: Int)

    func addToQueue(_ song: Song)
    func addToQueueNext(_ song: Song)
    func removeFromQueue(atAbsolute index: Int)
    func moveInUpNext(from source: IndexSet, to destination: Int)
    func clearQueue()
    func replaceQueue(_ songs: [Song], startIndex: Int)

    func setRepeatMode(_ mode: RepeatMode)
    func setShuffleEnabled(_ enabled: Bool)
    func applyEQToggle(enabled: Bool)
    func applyEffectiveVolume()

    var volume: Float { get set }
    var userVolume: Float { get set }
    var eqEnabled: Bool { get }
    var isPlaying: Bool { get }
    var currentSong: Song? { get }
    var currentTime: TimeInterval { get }
    var queue: [Song] { get }
    var currentIndex: Int { get }
    var repeatMode: RepeatMode { get }
    var shuffleEnabled: Bool { get }

    // The queue projections travel with `queue` and `currentIndex` deliberately. An index resolved
    // against one backend and used against another backend's array is not a stale reading, it is an
    // out-of-range crash — which is exactly what a half-routed split produced in the mini player.
    func nextSongIndex() -> Int?
    var upNext: [Song] { get }
    var upNextEntries: [(index: Int, song: Song)] { get }
    /// What the session's heartbeat is doing. Numeric and closed — safe for diagnostics.
    var heartbeatDiagnostics: PersistentHeartbeatDiagnostics { get }
}

/// The persistent side of a handoff, as the executor needs it.
@MainActor
protocol PersistentPlaybackSessionPort: AnyObject {
    /// Where the router sends transport while this backend holds authority.
    var transport: any PersistentTransportRouting { get }

    var isTransportActive: Bool { get }
    /// Adopt the queue being handed over. Starts nothing.
    func adopt(_ snapshot: PlaybackSessionSnapshot)
    /// Adopt the source that selection already materialized and inspected, rather than preparing it
    /// a second time.
    func adopt(preparedSource: GaplessPreparedTrack) async
    /// Install the render-observed first-audible callback. Must be in place before the start, or
    /// the boundary it latches could pass unobserved.
    func installAudibleObserver(_ observer: @escaping @MainActor () -> Void)
    func clearAudibleObserver()
    /// Begin playback, and begin driving the session.
    ///
    /// `sessionGeneration` is the planning generation this session was selected under. It travels
    /// with the start so the heartbeat can be tied to it: a loop belonging to a replaced session
    /// must not drain boundaries for its successor, and a generation comparison is what makes that
    /// checkable rather than dependent on cooperative cancellation landing in time.
    ///
    /// Throws if the backend refused to start.
    func start(sessionGeneration: UInt64) async throws
    /// Tear down whatever transport was partially brought up. Idempotent, and safe on a backend
    /// that never started.
    func tearDown()
}

// MARK: - Executor

/// Executes one finalized `PlaybackSessionSelectionPlan` and starts **exactly one** backend.
///
/// **Isolated on purpose.** It plans nothing, inspects no media, and holds no router: it consumes a
/// plan that was already finalized elsewhere and performs the ordered sequence that moves ownership
/// from one engine to the other. Lane 3D-B1b Core wires it to tests only —
/// `ApplicationPlaybackRouter.play(...)` still routes to legacy unconditionally.
///
/// **Why the order is the design.** Ownership is granted before the selected backend can become
/// audible, and legacy is proven released before persistent is granted anything, so the count of
/// backends holding the audio session, Now Playing, scrobble credit and the visualizer feed is
/// never two. Quiescence is `quiesceForPersistentSession()` and never `stop()`: stopping submits a
/// scrobble, clears Now Playing and nils `currentSong`, which would destroy the very session
/// persistent is adopting and double-credit a play that has not finished.
@MainActor
final class PlaybackSessionPlanExecutor {

    private let legacy: any LegacyPlaybackSessionPort
    private let persistent: any PersistentPlaybackSessionPort

    /// The single source of truth for who owns audio. Held, never duplicated.
    let ownership: PlaybackOwnershipCoordinator

    /// The last execution's result, for diagnostics.
    private(set) var lastOutcome: PlaybackSessionExecutionOutcome?

    /// The session preserved by the most recent handoff attempt, captured before teardown. While
    /// ownership is moving this — not the quiesced `AVQueuePlayer` — is the queue authority. It is
    /// deliberately not cleared afterwards: a completed handoff's snapshot is the record of what
    /// was handed over, and nothing routes off it.
    private(set) var preservedSnapshot: PlaybackSessionSnapshot?

    init(legacy: any LegacyPlaybackSessionPort,
         persistent: any PersistentPlaybackSessionPort,
         ownership: PlaybackOwnershipCoordinator = PlaybackOwnershipCoordinator()) {
        self.legacy = legacy
        self.persistent = persistent
        self.ownership = ownership
    }

    #if DEBUG
    /// Counts each step of the sequence, so "exactly once" is a checkable property rather than an
    /// asserted one. DEBUG-only, like the adapters' delegation counters.
    private(set) var stepCounts: [String: Int] = [:]
    private func count(_ step: String) { stepCounts[step, default: 0] += 1 }
    func resetStepCounts() { stepCounts.removeAll() }
    #else
    @inline(__always) private func count(_ step: String) {}
    #endif

    // MARK: - Execution

    /// Execute a finalized plan.
    ///
    /// `currentGeneration` is the newest request the caller has issued. A plan whose request does
    /// not match it has been superseded while it was being prepared, and executing it would start
    /// the queue the user has already moved on from.
    ///
    /// **One execution at a time.** The persistent path suspends at its adopt and start, so a
    /// caller that overlapped two executions could interleave them; serializing calls is the
    /// caller's job, and the generation check is what lets it drop the loser rather than run it.
    /// Nothing calls this in production yet, and the lane that wires it owns that serialization.
    @discardableResult
    func execute(plan: PlaybackSessionSelectionPlan,
                 request: PlaybackSessionSelectionRequest,
                 currentGeneration: UInt64) async -> PlaybackSessionExecutionOutcome {
        // Stale rejection is a generation comparison, and a superseded plan releases whatever it
        // holds so it can never be adopted afterwards.
        guard request.generation == currentGeneration else {
            release(plan)
            return settle(.superseded)
        }

        // Neither backend can start mid-track in this lane. Persistent has no resume-from-offset
        // path, and legacy cannot be started-then-seeked: `AudioEngine.play` defers its item swap
        // by 50 ms, so the seek would target the outgoing item. Starting at zero instead would play
        // the wrong audio, which is worse than declining.
        guard request.startOffsetSeconds <= 0 else {
            release(plan)
            return settle(.refused(.midTrackResumeUnsupported))
        }

        switch plan {
        case .legacy, .failed:
            // A failed selection is legacy-owned by definition: `PlaybackSessionSelectionPlan`
            // reports `.legacy` as its planned backend, because falling back happens before
            // anything is audible. Refusing to start would leave a Play press doing nothing.
            return settle(executeLegacy(request: request))
        case .persistent(let source, _):
            return settle(await executePersistent(source: source, request: request))
        }
    }

    /// Legacy plan: no quiescence, no persistent construction, no persistent start.
    private func executeLegacy(request: PlaybackSessionSelectionRequest)
        -> PlaybackSessionExecutionOutcome {
        let snapshot = handoffSnapshot(for: request)
        guard snapshot.currentSong != nil else { return .refused(.emptySession) }

        // Deliberately no `quiesceForPersistentSession()`: legacy already owns transport, and
        // tearing it down here would destroy the session it is about to play.
        ownership.grant(.legacy)
        count("grantLegacy")
        legacy.adopt(snapshot)
        count("adoptLegacy")
        legacy.start(snapshot)
        count("startLegacy")
        return .started(.legacy)
    }

    /// Persistent plan: the handoff sequence, in the only order that keeps the owner count at one.
    private func executePersistent(source: PreparedPersistentSource,
                                   request: PlaybackSessionSelectionRequest) async
        -> PlaybackSessionExecutionOutcome {
        // Consumability, checked before anything is torn down. A source that has already been
        // adopted cannot be adopted again, and discovering that *after* quiescing would have
        // silenced legacy for nothing.
        guard !source.isConsumed else { return .refused(.representationUnconfirmed) }

        let snapshot = handoffSnapshot(for: request)
        guard snapshot.currentSong != nil else {
            source.release()
            return .refused(.emptySession)
        }
        // Preserved BEFORE teardown: teardown removes the items and observers that would otherwise
        // be the only record of where playback was.
        preservedSnapshot = snapshot
        count("preserveSnapshot")

        legacy.quiesceForPersistentSession()
        count("quiesce")

        // One check, not five: `isTransportActive` is already defined as rate, current item, queued
        // items or playing. `isPlaying == false` alone would prove nothing — a paused
        // `AVQueuePlayer` still holds its items, its observers and its claim on the session.
        guard !legacy.transportState.isTransportActive else {
            source.release()
            return fallbackToLegacy(from: snapshot, reason: .legacyTransportNotReleased)
        }

        return await startPersistent(source: source, snapshot: snapshot,
                                     sessionGeneration: request.generation)
    }

    /// Grant, adopt, observe, start — in that order, with the grant before anything can be heard.
    private func startPersistent(source: PreparedPersistentSource,
                                 snapshot: PlaybackSessionSnapshot,
                                 sessionGeneration: UInt64) async
        -> PlaybackSessionExecutionOutcome {
        ownership.grant(.persistent)
        count("grantPersistent")

        guard let track = source.consume() else {
            // Unreachable via `execute`, which validates consumability first; handled rather than
            // forced because an unadoptable source must never leave persistent holding authority.
            return fallbackToLegacy(from: snapshot, reason: .representationUnconfirmed)
        }
        persistent.adopt(snapshot)
        count("adoptPersistentQueue")
        await persistent.adopt(preparedSource: track)
        count("adoptPreparedSource")

        // Weakly captured, and cleared in teardown: the callback outlives this call, and a strong
        // capture would tie the ownership coordinator's lifetime to a controller's.
        let coordinator = ownership
        persistent.installAudibleObserver { [weak coordinator] in
            // Idempotent and guarded on having an owner, so later firings — a repeat, or the extra
            // occurrences a seek legitimately produces — are harmless by construction. It means
            // "an occurrence became audible", never "a new session started".
            coordinator?.markAudibleBoundaryReached()
        }
        count("installAudibleObserver")

        do {
            try await persistent.start(sessionGeneration: sessionGeneration)
            count("startPersistent")
            return .started(.persistent)
        } catch {
            return fallbackToLegacy(from: snapshot, reason: .persistentStartFailed)
        }
    }

    /// Pre-audible fallback, and only pre-audible.
    ///
    /// Once the render clock has reported a first audible sample the latch is closed and this
    /// refuses: cutting over to a different engine mid-track is a worse outcome for the listener
    /// than an error. Persistent authority is revoked **before** legacy is rebuilt, so the owner
    /// count never transiently reads two.
    private func fallbackToLegacy(from snapshot: PlaybackSessionSnapshot,
                                  reason: SafePlaybackRoutingFailure)
        -> PlaybackSessionExecutionOutcome {
        guard ownership.isFallbackPermitted else { return .persistentRetained(reason) }

        persistent.tearDown()
        count("tearDownPersistent")
        persistent.clearAudibleObserver()
        count("clearAudibleObserver")
        ownership.release()
        count("revokePersistent")
        legacy.adopt(snapshot)
        count("adoptLegacy")
        ownership.grant(.legacy)
        count("grantLegacy")
        legacy.start(snapshot)
        count("startLegacy")
        return .fellBackToLegacy(reason)
    }

    // MARK: - Session identity

    /// The session being started: the requested occurrences, positionally, carrying the modes the
    /// live session already holds.
    ///
    /// Occurrences come from the request because that is the session the user asked for; repeat,
    /// shuffle, context, volume and EQ come from the capture because those belong to the session
    /// being handed over rather than to the request. Duplicate song ids stay distinct — the index
    /// is a position, never an identity lookup.
    private func handoffSnapshot(for request: PlaybackSessionSelectionRequest)
        -> PlaybackSessionSnapshot {
        var snapshot = legacy.captureSnapshot(startOffsetSeconds: request.startOffsetSeconds)
        snapshot.songs = request.songs
        snapshot.currentIndex = request.songs.indices.contains(request.startIndex)
            ? request.startIndex : 0
        snapshot.startOffsetSeconds = request.startOffsetSeconds
        return snapshot
    }

    /// A plan that will not be executed must not stay adoptable.
    private func release(_ plan: PlaybackSessionSelectionPlan) {
        if case .persistent(let source, _) = plan { source.release() }
    }

    private func settle(_ outcome: PlaybackSessionExecutionOutcome)
        -> PlaybackSessionExecutionOutcome {
        lastOutcome = outcome
        return outcome
    }
}
