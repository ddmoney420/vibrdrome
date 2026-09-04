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
/// authority is the gapless session. The mirrored values below are re-read *from* that session and
/// are never written by anything else, so they are a view of the authority rather than a second
/// one — which is the failure this whole lane is built to avoid.
///
/// `GaplessPlaybackController` is never exposed to application callers.
/// **`@Observable` on purpose.** SwiftUI re-renders because it observed a stored property being
/// read. `AudioEngine` is `@Observable`, so every legacy-routed read registers a dependency and the
/// UI updates; `GaplessPlaybackSession` is not, so a computed property reading through to it
/// registers nothing. Routing the application's state reads here without this made the mini player
/// render once with whatever was current at first draw and then never update again while audio
/// advanced underneath it. The mirrored values below are what makes the persistent path observable:
/// they are stored, so reading them is trackable, and the heartbeat refreshes them.
@MainActor
@Observable
final class PersistentApplicationPlaybackAdapter: PersistentTransportRouting {
    @ObservationIgnored private let assembly: PersistentPlaybackAssembly

    /// Presentation projection of what was handed to `replaceQueue`. Keyed lookups only — the
    /// gapless session remains the authority on position and playback state.
    private var songsByID: [String: Song] = [:]
    private var queueOrder: [String] = []

    // MARK: - Observable mirror
    //
    // Refreshed from the session and the render clock, which remain the authority — these are a
    // *view* of that authority, not a second copy of it. Nothing writes to them except
    // `refreshObservedState`, and nothing reads the session directly for presentation, so the two
    // cannot drift into disagreeing about what is playing.

    private(set) var currentIndex = 0
    private(set) var currentSong: Song?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var queue: [Song] = []
    private(set) var upNext: [Song] = []
    private(set) var upNextEntries: [(index: Int, song: Song)] = []
    private(set) var repeatMode: RepeatMode = .off
    private(set) var shuffleEnabled = false
    /// Duration of the audible track: **decoded** frames when its segment is on the timeline
    /// (authoritative — the audio that will actually render), else the server metadata.
    private(set) var duration: TimeInterval = 0
    /// The production notion from issue #90: the larger of decoded and server-reported durations,
    /// because some VBR/FLAC files under-report and the UI would show 0:00 remaining early.
    private(set) var effectiveDuration: TimeInterval = 0
    /// Next position in playback order, resolved by the same session that owns the queue.
    @ObservationIgnored private var nextIndex: Int?

    func nextSongIndex() -> Int? { nextIndex }

    /// Re-read everything the application presents from the session and the clock.
    ///
    /// Called after every heartbeat tick and immediately after each transport command, so the UI
    /// reflects a command at once rather than up to one heartbeat interval later.
    func refreshObservedState() {
        let index = session.queue.currentIndex
        currentIndex = index
        queue = queueOrder.compactMap { songsByID[$0] }
        currentSong = queueOrder.indices.contains(index) ? songsByID[queueOrder[index]] : nil
        isPlaying = session.isPlaying
        currentTime = assembly.backend
            .clockReading(generation: session.queue.generation).elapsedSeconds
        repeatMode = session.queue.repeatMode
        shuffleEnabled = session.queue.shuffleEnabled
        nextIndex = session.nextIndex(after: index, manual: false)
        refreshDurations()
        publishNowPlaying()

        // The linear tail, matching the legacy contract: no shuffle awareness and no cap.
        upNext = queue.indices.contains(index + 1) ? Array(queue[(index + 1)...]) : []

        // Playback order, capped at five — taken from the session's own planning so repeat and
        // shuffle are honoured by the component that will actually schedule them, rather than
        // re-derived here and allowed to disagree with what plays.
        let planned = session.plannedItemIDs(depth: 6).dropFirst()
        upNextEntries = planned.compactMap { itemID in
            guard let position = session.queue.items.firstIndex(where: { $0.id == itemID }),
                  queue.indices.contains(position) else { return nil }
            return (index: position, song: queue[position])
        }
    }

    // MARK: - Now Playing

    /// The persistent session's Now Playing publisher — dormant until this adapter wires it.
    ///
    /// Driven from **render-observed boundaries** (`controller.observedBoundaries`), never from
    /// preparation or scheduling: on this architecture the next track is decoded and handed to the
    /// node long before it is heard, and publishing at that point would show the wrong song on the
    /// lock screen for the rest of the outgoing track.
    @ObservationIgnored let nowPlaying = GaplessNowPlayingBridge()
    /// How many observed boundaries have been published. The controller's list is append-only for
    /// the life of a session and cleared only by `controller.stop()`, which this adapter always
    /// accompanies with a reset of this cursor.
    @ObservationIgnored private var publishedBoundaryCount = 0

    private func wireNowPlaying() {
        nowPlaying.publishMetadata = { [weak self] update in
            guard let self, let song = self.songsByID[update.songID] else { return }
            NowPlayingManager.shared.update(song: song, isPlaying: update.isPlaying)
            // `update(song:)` writes the server duration; correct it to the effective one so the
            // system's remaining time matches the audio that will actually render (issue #90).
            if self.effectiveDuration > 0 {
                NowPlayingManager.shared.updateDuration(self.effectiveDuration)
            }
        }
        nowPlaying.publishElapsed = { seconds, _ in
            NowPlayingManager.shared.updateElapsedTime(seconds)
        }
    }

    /// Publish boundaries that became audible since the last refresh, then the elapsed tick.
    private func publishNowPlaying() {
        let boundaries = controller.observedBoundaries
        if publishedBoundaryCount > boundaries.count { publishedBoundaryCount = 0 }
        for event in boundaries[publishedBoundaryCount...] {
            nowPlaying.trackBecameAudible(GaplessNowPlayingUpdate(
                songID: event.songID, itemID: event.itemID, playInstance: event.playInstance,
                queueGeneration: event.generation, tailGeneration: event.tailGeneration,
                scheduledStartFrame: event.scheduledStartFrame,
                observedRenderFrame: event.observedRenderFrame,
                queueIndex: currentIndex, elapsedSeconds: 0, isPlaying: isPlaying))
        }
        publishedBoundaryCount = boundaries.count
        // Rate-limited by the bridge to 1 Hz, matching the legacy periodic observer's cadence.
        if nowPlaying.publishedInstance != nil {
            nowPlaying.publishElapsed(seconds: currentTime, isPlaying: isPlaying)
        }
    }

    /// Duration of the audible track. Decoded frames from its timeline segment are authoritative
    /// (that is the audio that will render); server metadata fills in before materialization.
    private func refreshDurations() {
        let server = currentSong.flatMap { song in
            session.songDurations[song.id] ?? song.duration.map(TimeInterval.init)
        } ?? 0
        let decoded = controller.audiblePlayInstance.flatMap { instance in
            assembly.backend.cachedReadout.segments
                .first { $0.playInstance == instance }
                .map { Double($0.frameCount) / GaplessRenderFormat.sampleRate }
        } ?? 0
        duration = decoded > 0 ? decoded : server
        effectiveDuration = max(decoded, server)
    }

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
        wireNowPlaying()
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
        // Weakly captured: the heartbeat is owned by this adapter, so a strong capture here would
        // be a cycle that keeps a finished session's engine alive.
        heartbeat.start(controller: controller, generation: sessionGeneration) { [weak self] in
            self?.refreshObservedState()
        }
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
        refreshObservedState()
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
    func pause() {
        count("pause")
        controller.pause()
        refreshObservedState()
        publishPlaybackStateNow()
    }
    func resume() {
        count("resume")
        try? controller.resume()
        refreshObservedState()
        publishPlaybackStateNow()
    }

    /// Rate and elapsed, published immediately — pause, resume and seek cannot wait a tick, or the
    /// lock screen visibly shows the old state. Mirrors the legacy `updatePlaybackState` calls.
    private func publishPlaybackStateNow() {
        guard nowPlaying.publishedInstance != nil else { return }
        nowPlaying.publishElapsedImmediately(seconds: currentTime, isPlaying: isPlaying)
        NowPlayingManager.shared.updatePlaybackState(isPlaying: isPlaying, elapsed: currentTime)
    }

    /// Stop ends the session, so the heartbeat goes with it — before the controller stops, so no
    /// tick can observe a half-torn-down session.
    func stop() {
        count("stop")
        heartbeat.cancel()
        controller.stop()
        // A user Stop ends what the system should display; a handoff does not (see `quiesce`).
        nowPlaying.reset()
        publishedBoundaryCount = 0
        NowPlayingManager.shared.clear()
        refreshObservedState()
    }

    func togglePlayPause() {
        count("togglePlayPause")
        if session.isPlaying { controller.pause() } else { try? controller.resume() }
        refreshObservedState()
        publishPlaybackStateNow()
    }

    func next() {
        count("next")
        Task { [weak self, controller] in
            try? await controller.next()
            self?.refreshObservedState()
        }
    }

    func previous(currentElapsed: TimeInterval) {
        count("previous")
        Task { [weak self, controller] in
            // The resolved destination is the controller's own business; the caller only needs the
            // command issued, and the refresh below is what the UI reads.
            _ = try? await controller.previous(elapsedSeconds: currentElapsed)
            self?.refreshObservedState()
        }
    }

    /// Previous, resolving elapsed from the render clock rather than from the caller.
    ///
    /// The 3-second restart threshold is measured against how far into the track playback actually
    /// is, and while persistent owns audio the legacy engine's `currentTime` is zero — reading it
    /// would make Previous always skip back a track instead of restarting the current one.
    func previous() { previous(currentElapsed: currentTime) }

    func seek(to time: TimeInterval) {
        count("seek")
        Task { [weak self, controller] in
            try? await controller.seek(toSeconds: time)
            self?.refreshObservedState()
            // Same play instance continues from a new position — no metadata change, but the
            // system's elapsed must jump now rather than at the next rate-limited tick.
            self?.publishPlaybackStateNow()
        }
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
        Task { [weak self, controller] in
            try? await controller.addToQueue(songID: song.id)
            self?.refreshObservedState()
        }
    }

    func addToQueueNext(_ song: Song) {
        count("addToQueueNext")
        songsByID[song.id] = song
        let insertAt = min(session.queue.currentIndex + 1, queueOrder.count)
        queueOrder.insert(song.id, at: insertAt)
        Task { [weak self, controller] in
            try? await controller.playNext(songID: song.id)
            self?.refreshObservedState()
        }
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
        Task { [weak self, controller] in
            try? await controller.remove(itemID: item.id)
            self?.refreshObservedState()
        }
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
        Task { [weak self, controller] in
            try? await controller.move(itemID: item.id, to: destination)
            self?.refreshObservedState()
        }
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
        Task { [weak self, controller] in
            try? await controller.setRepeatMode(mode)
            self?.refreshObservedState()
        }
    }

    func setShuffleEnabled(_ enabled: Bool) {
        count("setShuffleEnabled")
        Task { [weak self, controller] in
            try? await controller.setShuffleEnabled(enabled)
            self?.refreshObservedState()
        }
    }

    // MARK: - Processing

    /// User volume, applied at the player node.
    ///
    /// The node rather than the gain stage on purpose: the gain stage carries ReplayGain, scheduled
    /// per track at its audible boundary, and folding the user's setting into it would make a
    /// volume change land at the next track instead of now.
    /// The user's setting, stored separately from the applied output level.
    ///
    /// Split the same way `AudioEngine` splits it: the node's volume is a *product* of the user
    /// setting and the sleep-timer fade, so reading it back as the user setting would fold the fade
    /// in again on the next apply and drive the volume to zero.
    @ObservationIgnored private var storedUserVolume: Float = 1

    var userVolume: Float {
        get { storedUserVolume }
        set {
            count("userVolume")
            storedUserVolume = max(0, min(1, newValue))
            applyEffectiveVolume()
        }
    }

    /// Effective output volume. Identical to `userVolume` here — ReplayGain is a separate stage in
    /// this graph rather than a multiplier folded into the volume, which is what lets a gain change
    /// be scheduled at a frame.
    var volume: Float {
        get { userVolume }
        set { userVolume = newValue }
    }

    /// Apply the effective output volume.
    ///
    /// The sleep-timer fade is folded in the same way `AudioEngine.applyEffectiveVolume` folds it,
    /// because the timer now routes through the façade: without this, a sleep timer set during a
    /// persistent session would count down and cut the audio dead instead of fading it. ReplayGain
    /// is deliberately *not* folded in here — it is a scheduled gain-stage event on this graph, not
    /// a volume multiplier.
    func applyEffectiveVolume() {
        count("applyEffectiveVolume")
        let faded = storedUserVolume * SleepTimer.shared.fadeFactor
        assembly.backend.engine.player.volume = max(0, min(1, faded))
    }

    /// Toggle EQ mid-playback. Ramped by the stage, and a true transparent bypass rather than flat
    /// bands, so the change cannot click across a boundary.
    func applyEQToggle(enabled: Bool) {
        count("applyEQToggle")
        assembly.backend.engine.setEQEnabled(enabled)
    }

    var eqEnabled: Bool { assembly.backend.engine.eqStage.settings.isEnabled }

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
        // Handoff, not a user Stop: the bridge forgets its session so nothing stale is accepted
        // later, but the system display is left for the next owner to overwrite — clearing it here
        // would blank the lock screen in the instant between backends.
        nowPlaying.reset()
        publishedBoundaryCount = 0
    }
}
