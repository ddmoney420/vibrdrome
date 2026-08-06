import Foundation

/// Which backend owns the **current playback session**.
///
/// A session concept, not a global one: the decision is made per explicit playback request and holds
/// until that session ends. Nothing about it is a property of the process.
enum PlaybackSessionBackend: String, Equatable, Sendable {
    case legacy
    case persistent
}

/// Why a routing attempt could not proceed. Coarse and closed — these reach diagnostics, so no
/// credential, URL, header or file path may appear.
enum SafePlaybackRoutingFailure: String, Equatable, Sendable, CaseIterable {
    case persistentConstructionFailed
    case sourcePreparationFailed
    case representationUnconfirmed
    case policySelectedLegacy
    /// Legacy still held transport after quiescence, so persistent was never granted authority.
    /// Granting it while the old `AVQueuePlayer` still holds items and observers is exactly the
    /// two-owner state the ownership invariant exists to prevent.
    case legacyTransportNotReleased
    /// The persistent backend refused to start. Recoverable only before anything has been heard.
    case persistentStartFailed
    /// The plan named a mid-track start, which neither backend can honour in this lane. Starting at
    /// zero instead would play the wrong audio, which is worse than declining.
    case midTrackResumeUnsupported
    /// The plan named no playable occurrence, so there was no session to start.
    case emptySession
}

/// How far selection has got for the current session.
enum PlaybackSessionSelectionState: Equatable, Sendable {
    case idle
    case evaluating
    case preparing
    case legacy(reason: PlaybackBackendDecisionReason)
    case persistent(reason: PlaybackBackendDecisionReason)
    case failed(reason: SafePlaybackRoutingFailure)

    /// The backend actually owning audio, if any. `nil` while no session is settled.
    var backend: PlaybackSessionBackend? {
        switch self {
        case .legacy, .failed: .legacy
        case .persistent: .persistent
        case .idle, .evaluating, .preparing: nil
        }
    }

    var describedForDiagnostics: String {
        switch self {
        case .idle: "Idle"
        case .evaluating: "Evaluating"
        case .preparing: "Preparing"
        case .legacy(let reason): "Legacy (\(reason.rawValue))"
        case .persistent(let reason): "Persistent (\(reason.rawValue))"
        case .failed(let reason): "Failed (\(reason.rawValue))"
        }
    }
}

/// The DEBUG-only rollout switch for persistent routing.
///
/// **Defaults to Off, and does not exist in Release.** Reading it constructs nothing, enabling it
/// starts nothing, and changing it mid-playback does not move the current session — the new value
/// applies to the *next* explicit playback request, because switching a backend under audible audio
/// is precisely what this whole design exists to prevent.
enum PersistentRoutingSetting {
    #if DEBUG
    static let defaultsKey = "debugUsePersistentPlaybackEngine"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }
    #else
    /// Release has no flag path at all: persistent routing is unreachable.
    static var isEnabled: Bool { false }
    #endif
}

/// The application-facing adapter over the persistent gapless controller.
///
/// **Two impedance mismatches to bridge.** The application contract is synchronous and speaks in
/// `Song` values; `GaplessPlaybackController` is `async throws` and speaks in song IDs. So every
/// operation here wraps the controller call in a `Task` — matching the application contract's
/// fire-and-forget shape, the same as the legacy adapter, where `AudioEngine` also does its real
/// work asynchronously behind a synchronous call.
///
/// **The `Song` view is a projection, not a second queue.** This adapter keeps the `[Song]` array it
/// was handed so it can answer `currentSong`, `queue` and `currentIndex`, but the scheduling
/// authority is the gapless session — index and playing state are read from it, never stored here.
/// A stored copy would be a second runtime queue authority, which is the failure this whole lane is
/// built to avoid.
///
/// `GaplessPlaybackController` is never exposed to application callers.
@MainActor
final class PersistentApplicationPlaybackAdapter: PersistentTransportRouting {
    private let assembly: PersistentPlaybackAssembly

    /// Presentation projection of what was handed to `replaceQueue`. Keyed lookups only — the
    /// gapless session remains the authority on position and playback state.
    private var songsByID: [String: Song] = [:]
    private var queueOrder: [String] = []

    #if DEBUG
    /// Counts delegated calls, so a test can prove one application operation produces exactly one
    /// controller operation — the same property the legacy adapter's counters give.
    private(set) var delegatedCallCounts: [String: Int] = [:]
    private func count(_ name: String) { delegatedCallCounts[name, default: 0] += 1 }
    func resetDelegationCounts() { delegatedCallCounts.removeAll() }
    #else
    @inline(__always) private func count(_ name: String) {}
    #endif

    init(assembly: PersistentPlaybackAssembly) {
        self.assembly = assembly
    }

    private var controller: GaplessPlaybackController { assembly.controller }
    private var session: GaplessPlaybackSession { assembly.session }

    // MARK: - Heartbeat

    /// The one thing that drives `tick()` for this session.
    ///
    /// Owned here rather than by a view, a scene, the app or a global display timer: this object's
    /// life is the persistent session's life, so the heartbeat cannot outlive the transport it
    /// drives, and every path that ends the session already goes through `stop()` or `quiesce()`.
    private let heartbeat = PersistentPlaybackHeartbeat()

    var heartbeatDiagnostics: PersistentHeartbeatDiagnostics { heartbeat.diagnostics }

    /// Begin driving the session that has just been started.
    ///
    /// Called by the session port immediately after the controller's transport start, so the
    /// heartbeat cannot exist before there is a started session for it to drive — it never runs at
    /// launch, during planning, during media inspection, or over a passively-constructed assembly.
    func startHeartbeat(sessionGeneration: UInt64) {
        heartbeat.start(controller: controller, generation: sessionGeneration)
    }

    /// Stop driving. Idempotent, and safe when nothing is running.
    func cancelHeartbeat() { heartbeat.cancel() }

    #if DEBUG
    var heartbeatForTesting: PersistentPlaybackHeartbeat { heartbeat }
    #endif

    /// Whether this adapter currently owns audible playback.
    var isTransportActive: Bool {
        assembly.backend.engine.player.isPlaying || session.isPlaying
    }

    // MARK: - Queue projection

    /// Adopt the `Song` view for a queue the caller is about to play.
    func adoptQueue(_ songs: [Song]) {
        songsByID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        queueOrder = songs.map(\.id)
    }

    var queue: [Song] { queueOrder.compactMap { songsByID[$0] } }

    var currentIndex: Int { session.queue.currentIndex }

    var currentSong: Song? {
        let index = session.queue.currentIndex
        guard queueOrder.indices.contains(index) else { return nil }
        return songsByID[queueOrder[index]]
    }

    // MARK: - Transport

    func play(song: Song, from newQueue: [Song]?, at index: Int) {
        count("play")
        let songs = newQueue ?? [song]
        adoptQueue(songs)
        let startIndex = songs.indices.contains(index) ? index : 0
        Task { [controller] in
            try? await controller.replaceQueue(songIDs: songs.map(\.id), startIndex: startIndex)
            try? await controller.play()
        }
    }

    // Pause deliberately leaves the heartbeat running. It is idle-safe while paused and cannot
    // advance anything: the node is stopped so the render clock is frozen, which means no boundary
    // is observed and the session advances by zero frames; the in-flight chunk count stays at the
    // scheduler's target so `pump()` returns immediately without touching the pool; and the
    // prefetch window is already full so `replenishTail` returns. Keeping one loop across a pause
    // is also what makes "resume continues the same session" true by construction rather than by
    // restarting something and hoping it is the same one.
    func pause() { count("pause"); controller.pause() }
    func resume() { count("resume"); try? controller.resume() }

    /// Stop ends the session, so the heartbeat goes with it — before the controller stops, so no
    /// tick can observe a half-torn-down session.
    func stop() {
        count("stop")
        heartbeat.cancel()
        controller.stop()
    }

    func togglePlayPause() {
        count("togglePlayPause")
        if session.isPlaying { controller.pause() } else { try? controller.resume() }
    }

    func next() {
        count("next")
        Task { [controller] in try? await controller.next() }
    }

    func previous(currentElapsed: TimeInterval) {
        count("previous")
        Task { [controller] in try? await controller.previous(elapsedSeconds: currentElapsed) }
    }

    /// Previous, resolving elapsed from the render clock rather than from the caller.
    ///
    /// The 3-second restart threshold is measured against how far into the track playback actually
    /// is, and while persistent owns audio the legacy engine's `currentTime` is zero — reading it
    /// would make Previous always skip back a track instead of restarting the current one.
    func previous() { previous(currentElapsed: currentTime) }

    func seek(to time: TimeInterval) {
        count("seek")
        Task { [controller] in try? await controller.seek(toSeconds: time) }
    }

    func skipToIndex(_ index: Int) {
        count("skipToIndex")
        guard queueOrder.indices.contains(index) else { return }
        let songs = queue
        Task { [controller] in
            try? await controller.replaceQueue(songIDs: songs.map(\.id), startIndex: index)
            try? await controller.play()
        }
    }

    // MARK: - Queue mutation

    func addToQueue(_ song: Song) {
        count("addToQueue")
        songsByID[song.id] = song
        queueOrder.append(song.id)
        Task { [controller] in try? await controller.addToQueue(songID: song.id) }
    }

    func addToQueueNext(_ song: Song) {
        count("addToQueueNext")
        songsByID[song.id] = song
        let insertAt = min(session.queue.currentIndex + 1, queueOrder.count)
        queueOrder.insert(song.id, at: insertAt)
        Task { [controller] in try? await controller.playNext(songID: song.id) }
    }

    func replaceQueue(_ songs: [Song], startIndex: Int) {
        count("replaceQueue")
        adoptQueue(songs)
        Task { [controller] in
            try? await controller.replaceQueue(songIDs: songs.map(\.id), startIndex: startIndex)
        }
    }

    /// Remove by absolute queue position.
    ///
    /// The position is resolved to the gapless session's own occurrence identity before the removal
    /// is issued: two positions can hold the same song id, and removing "the song" rather than "the
    /// occurrence" would drop the wrong one.
    func removeFromQueue(atAbsolute index: Int) {
        count("removeFromQueue")
        guard let item = session.queue.items.indices.contains(index)
            ? session.queue.items[index] : nil else { return }
        if queueOrder.indices.contains(index) {
            let removed = queueOrder.remove(at: index)
            if !queueOrder.contains(removed) { songsByID[removed] = nil }
        }
        Task { [controller] in try? await controller.remove(itemID: item.id) }
    }

    /// Reorder within Up Next. Positions are relative to the queue as a whole, matching the legacy
    /// contract, and are resolved to occurrence identities for the same reason as removal.
    func moveInUpNext(from source: IndexSet, to destination: Int) {
        count("moveInUpNext")
        guard let from = source.first,
              session.queue.items.indices.contains(from) else { return }
        let item = session.queue.items[from]
        if queueOrder.indices.contains(from) {
            let moved = queueOrder.remove(at: from)
            queueOrder.insert(moved, at: min(max(0, destination), queueOrder.count))
        }
        Task { [controller] in try? await controller.move(itemID: item.id, to: destination) }
    }

    func clearQueue() {
        count("clearQueue")
        songsByID.removeAll()
        queueOrder.removeAll()
        session.clearQueue()
    }

    // MARK: - Modes

    func setRepeatMode(_ mode: RepeatMode) {
        count("setRepeatMode")
        Task { [controller] in try? await controller.setRepeatMode(mode) }
    }

    func setShuffleEnabled(_ enabled: Bool) {
        count("setShuffleEnabled")
        Task { [controller] in try? await controller.setShuffleEnabled(enabled) }
    }

    // MARK: - Processing

    /// User volume, applied at the player node.
    ///
    /// The node rather than the gain stage on purpose: the gain stage carries ReplayGain, scheduled
    /// per track at its audible boundary, and folding the user's setting into it would make a
    /// volume change land at the next track instead of now.
    var userVolume: Float {
        get { assembly.backend.engine.player.volume }
        set {
            count("userVolume")
            assembly.backend.engine.player.volume = max(0, min(1, newValue))
        }
    }

    /// Effective output volume. Identical to `userVolume` here — ReplayGain is a separate stage in
    /// this graph rather than a multiplier folded into the volume, which is what lets a gain change
    /// be scheduled at a frame.
    var volume: Float {
        get { userVolume }
        set { userVolume = newValue }
    }

    func applyEffectiveVolume() {
        count("applyEffectiveVolume")
        assembly.backend.engine.player.volume = max(0, min(1, userVolume))
    }

    /// Toggle EQ mid-playback. Ramped by the stage, and a true transparent bypass rather than flat
    /// bands, so the change cannot click across a boundary.
    func applyEQToggle(enabled: Bool) {
        count("applyEQToggle")
        assembly.backend.engine.setEQEnabled(enabled)
    }

    var eqEnabled: Bool { assembly.backend.engine.eqStage.settings.isEnabled }

    // MARK: - Observable state, read from the session

    var isPlaying: Bool { session.isPlaying }
    var repeatMode: RepeatMode { session.queue.repeatMode }
    var shuffleEnabled: Bool { session.queue.shuffleEnabled }

    /// Elapsed position, from the render clock.
    ///
    /// The clock is the only honest source while persistent owns audio: it maps hardware time
    /// through the scheduled timeline to a position inside the current track, which is what the
    /// boundary accounting, seek and Previous all read.
    var currentTime: TimeInterval {
        assembly.backend.clockReading(generation: session.queue.generation).elapsedSeconds
    }

    /// Quiesce this backend so the other one can own audio. Idempotent.
    ///
    /// The heartbeat is cancelled first: every handover path — replacement, a switch to legacy,
    /// radio, a failed start, pre-audible fallback and the backend reset that follows it — reaches
    /// here, and a tick landing after the controller had stopped would be a stale session touching
    /// a backend that no longer belongs to it.
    func quiesce() {
        count("quiesce")
        heartbeat.cancel()
        controller.stop()
    }
}
