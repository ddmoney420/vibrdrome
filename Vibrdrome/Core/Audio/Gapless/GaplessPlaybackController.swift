import AVFoundation
import Foundation
import os.log

/// One item's journey from "we will need this" to "this is playing", timestamped.
///
/// Recorded so the preparation deadline can be *measured* rather than guessed: the only number that
/// matters is how much time was left between an item becoming ready and the moment it had to be
/// audible, and that cannot be reasoned about from code.
/// A bounded rolling window of one lead-time metric, for the Debug diagnostics display.
///
/// Bounded on purpose: a playback session produces thousands of transitions, and retaining every
/// sample to show an average would be the sort of unbounded history this engine spent a checkpoint
/// removing. 100 samples is enough for a stable average and costs 800 bytes.
struct GaplessLeadTimeWindow: Sendable {
    static let capacity = 100

    private(set) var samples: [TimeInterval] = []
    private(set) var latest: TimeInterval?

    /// Records a sample, discarding the oldest once the window is full.
    mutating func record(_ value: TimeInterval) {
        latest = value
        samples.append(value)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    var minimum: TimeInterval? { samples.min() }
    var average: TimeInterval? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }
    var count: Int { samples.count }
    var hasMeasurement: Bool { latest != nil }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        latest = nil
    }
}

/// The two lead-time windows, as the Debug screen reads them.
struct GaplessLeadTimeStatistics: Sendable {
    /// **ready → audible.** Preserved from the existing production definition: how much slack there
    /// was between an item being ready to schedule and the moment it had to be heard. It is NOT
    /// "requested → ready"; the label in the Debug screen says so, because silently redefining a
    /// metric is worse than an awkward name.
    var preparation = GaplessLeadTimeWindow()
    /// **scheduled → audible.** Time between the item's audio being handed to the player node and
    /// it becoming audible.
    var scheduling = GaplessLeadTimeWindow()

    mutating func reset() {
        preparation.reset()
        scheduling.reset()
    }
}

struct GaplessPreparationRecord: Sendable {
    let itemID: GaplessQueueItemID
    let songID: String
    let queueGeneration: UInt64
    var requestedAt: Date
    var readyAt: Date?
    var scheduledAt: Date?
    var audibleAt: Date?
    var failure: String?

    /// Time between the item being ready to schedule and it becoming audible.
    var preparationLeadTime: TimeInterval? {
        guard let readyAt, let audibleAt else { return nil }
        return audibleAt.timeIntervalSince(readyAt)
    }

    /// Time between the item's audio being handed to the player node and it becoming audible.
    var schedulingLeadTime: TimeInterval? {
        guard let scheduledAt, let audibleAt else { return nil }
        return audibleAt.timeIntervalSince(scheduledAt)
    }

    var preparationDuration: TimeInterval? {
        readyAt.map { $0.timeIntervalSince(requestedAt) }
    }
}

/// What to do when the next item is not ready in time for its boundary.
///
/// The default is `controlledWait`, chosen because the alternatives are all worse for a music
/// player: skipping loses a track the user asked for, stopping ends the album, and switching engines
/// mid-track cuts the output stream — the exact defect this architecture exists to remove. A wait is
/// the only option that keeps queue state correct and remains recoverable, and it is *reported*
/// rather than disguised as success.
enum GaplessDeadlinePolicy: String, Sendable, Equatable {
    /// Let the graph run dry and continue when the item arrives. Audible as a pause; never wrong.
    case controlledWait
    /// Stop after the current item, leaving the unavailable successor as pending work.
    case stopWithResumableState
}

/// A reported deadline miss. Never inferred — the engine says so explicitly.
struct GaplessDeadlineMiss: Sendable, Equatable {
    let itemID: GaplessQueueItemID
    let songID: String
    let policy: GaplessDeadlinePolicy
    /// Frames of shortfall, if the boundary had already passed when the item became ready.
    let lateByFrames: AVAudioFramePosition
}

/// Binds the queue session, the preparation window and the real-time backend into a playing system.
///
/// This is the only place the three meet. The session owns queue truth and transport policy, the
/// preparer owns getting bytes local and decoded, the backend owns the graph and the clock — and
/// none of them know about each other. Keeping the coordination here is what allowed the transport
/// policy to be tested with no audio and the tail mechanism to be tested with no queue.
///
/// **Driving.** `tick()` is the heartbeat: it observes boundaries from the render clock, advances the
/// session, and replenishes the scheduled tail. Production will call it from a display-link or timer;
/// tests call it from their polling loop, which is why the transport results are reproducible.
@MainActor
final class GaplessPlaybackController {
    let session: GaplessPlaybackSession
    let backend: GaplessRealTimeBackend
    let preparer: GaplessTrackPreparer
    let window: GaplessPrefetchWindow
    var deadlinePolicy: GaplessDeadlinePolicy = .controlledWait

    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessController")
    private(set) var preparationRecords: [GaplessQueueItemID: GaplessPreparationRecord] = [:]
    private(set) var deadlineMisses: [GaplessDeadlineMiss] = []
    /// Async preparation results that arrived after their generation was superseded.
    private(set) var staleResultCount = 0
    /// Bounded lead-time windows for the Debug diagnostics screen. Read-only to the UI; written only
    /// here, on the main actor, at the audible boundary — never on the render callback.
    private(set) var leadTimeStatistics = GaplessLeadTimeStatistics()
    /// Rations preparation work for planned occurrences.
    ///
    /// Without it, `replenishTail` re-attempted any not-yet-ready occurrence on every tick, so a
    /// permanently unplayable source produced 172-450 attempts in ~1.5 s. The pump may still observe
    /// a failed occurrence constantly; the gate is what stops it doing work each time.
    let preparationGate = GaplessPreparationGate()
    /// How many times each slot has begun a new play, plus any explicit retries.
    ///
    /// This is what separates "the pump asked again about the same planned play" from "this slot is
    /// being played again" — a Repeat All wrap and a Repeat One replay are new plays and must get a
    /// clean attempt, while a pump cycle that changed nothing must not.
    private var occurrenceEpochs: [GaplessQueueItemID: UInt64] = [:]
    /// Boundary events observed on the render clock, newest last.
    private(set) var observedBoundaries: [GaplessBoundaryEvent] = []
    /// Play instance of the currently audible segment.
    ///
    /// The tail position CANNOT be found by item ID: under Repeat All the same slot appears on the
    /// timeline more than once, so matching by ID finds the *first* (already played) occurrence,
    /// computes a tail that looks longer than it is, and schedules nothing — the engine runs dry a
    /// few tracks in. Play instance is unique per play, which is exactly what this needs.
    private(set) var audiblePlayInstance: GaplessPlayInstanceID?

    /// ReplayGain settings applied at each boundary.
    var replayGainSettings: GaplessReplayGainSettings = .off
    /// Server ReplayGain metadata per song.
    var replayGains: [String: ReplayGain] = [:]

    init(session: GaplessPlaybackSession, backend: GaplessRealTimeBackend,
         preparer: GaplessTrackPreparer, window: GaplessPrefetchWindow = GaplessPrefetchWindow()) {
        self.session = session
        self.backend = backend
        self.preparer = preparer
        self.window = window
        #if DEBUG
        // Registered weakly so the Debug diagnostics screen can read lead times. No effect on
        // playback, and compiled out of release builds.
        GaplessDiagnosticsRegistry.register(self)
        #endif
    }

    deinit {
        #if DEBUG
        // Nothing to unregister explicitly: the registry holds a weak reference and nils itself.
        #endif
    }

    // MARK: - Transport

    /// Start playback. The only path that activates the audio session.
    func play() async throws {
        try backend.prepareGraph()
        await replenishTail()
        try backend.start()
        session.play()
    }

    func pause() {
        backend.pause()
        session.pause()
    }

    func resume() throws {
        try backend.resume()
        session.play()
    }

    /// Stop everything and leave the graph reusable.
    /// Clear a failed occurrence and allow exactly one fresh attempt.
    ///
    /// A deliberate retry is a *new* occurrence, not a continuation: the retry epoch advances, so the
    /// permanent-failure record for the old one stays put and cannot be confused with the new
    /// attempt's state.
    func retryPreparation(itemID: GaplessQueueItemID) {
        guard let item = session.queue.item(id: itemID) else { return }
        let identity = GaplessPreparationIdentity(
            itemID: itemID, songID: item.songID, queueGeneration: session.queue.generation,
            occurrenceEpoch: occurrenceEpochs[itemID] ?? 0)
        _ = preparationGate.explicitRetry(identity)
        occurrenceEpochs[itemID] = (occurrenceEpochs[itemID] ?? 0) + 1
    }

    /// Occurrences that will not be retried without explicit action, for the application-facing
    /// state. A controller must not look plainly `playing` when nothing more can be produced.
    var hasPermanentPreparationFailure: Bool { preparationGate.permanentFailureCount > 0 }

    func stop() {
        // Every planned occurrence is abandoned; a pending retry deadline must not revive one after
        // the user has stopped.
        preparationGate.reset()
        occurrenceEpochs.removeAll()
        // Cleared when the session is stopped, not at every track boundary.
        leadTimeStatistics.reset()
        backend.stop()
        session.stop()
        observedBoundaries.removeAll()
        audiblePlayInstance = nil
    }

    /// Manual Next: resolve the destination under repeat/shuffle, replace the tail, restart there.
    func next() async throws {
        guard session.skipToNext() != nil else {
            stop()
            return
        }
        try await restartFromCurrentItem()
    }

    /// Manual Previous, honouring the production 3-second restart threshold.
    @discardableResult
    func previous(elapsedSeconds: TimeInterval) async throws
        -> GaplessTransportPolicy.PreviousDestination {
        let destination = session.skipToPrevious(elapsedSeconds: elapsedSeconds)
        try await restartFromCurrentItem()
        return destination
    }

    /// Seek within the audible item, then rebuild the future from there.
    func seek(toSeconds seconds: TimeInterval) async throws {
        let wasPlaying = backend.state == .playing
        let frame = AVAudioFramePosition(max(0, seconds) * backend.engine.renderFormat.sampleRate)
        session.seek(toFrame: frame)
        try await restartFromCurrentItem(sourceOffsetFrames: frame, resumePlaying: wasPlaying)
    }

    // MARK: - Queue mutations

    func playNext(songID: String) async throws {
        session.playNext(songID: songID)
        try await rebuildTailPreservingAudibleItem()
    }

    func addToQueue(songID: String) async throws {
        session.addToQueue(songID: songID)
        // Appending past the window cannot affect planned audio, so the tail is left alone.
        await replenishTail()
    }

    func remove(itemID: GaplessQueueItemID) async throws {
        let wasAudible = itemID == session.audibleItemID
        session.remove(itemID: itemID)
        if wasAudible {
            try await restartFromCurrentItem()
        } else {
            try await rebuildTailPreservingAudibleItem()
        }
    }

    func move(itemID: GaplessQueueItemID, to destination: Int) async throws {
        session.move(itemID: itemID, to: destination)
        try await rebuildTailPreservingAudibleItem()
    }

    func replaceQueue(songIDs: [String], startIndex: Int = 0) async throws {
        session.replaceQueue(songIDs: songIDs, startIndex: startIndex)
        try await restartFromCurrentItem()
    }

    func setRepeatMode(_ mode: RepeatMode) async throws {
        session.setRepeatMode(mode)
        try await rebuildTailPreservingAudibleItem()
    }

    func setShuffleEnabled(_ enabled: Bool) async throws {
        session.setShuffleEnabled(enabled)
        try await rebuildTailPreservingAudibleItem()
    }

    // MARK: - Tail management

    /// Replace only the not-yet-audible future, keeping the current track playing from where it is.
    ///
    /// "Keeping it playing" cannot mean leaving its audio alone: `resetTail()` stops the player node,
    /// which discards the audible segment's remaining audio along with the pending ones. So the
    /// current item is measured first, then re-scheduled from that offset — the listener hears it
    /// continue, and the timeline stays consistent with the audio.
    private func rebuildTailPreservingAudibleItem() async throws {
        guard let audibleID = session.audibleItemID,
              let offset = backend.audibleOffset(of: audibleID) else {
            try await restartFromCurrentItem()
            return
        }
        backend.resetTail()
        await replenishTail(sourceOffsetFrames: offset)
    }

    /// Restart the timeline from the session's current item — used by Next, Previous, seek, remove
    /// of the audible item, and queue replacement. The graph is never rebuilt.
    private func restartFromCurrentItem(sourceOffsetFrames: AVAudioFramePosition = 0,
                                        resumePlaying: Bool = true) async throws {
        backend.resetTail()
        await replenishTail(sourceOffsetFrames: sourceOffsetFrames)
        if resumePlaying, backend.state == .prepared || backend.state == .idle {
            try backend.start()
        }
    }

    /// Ensure the rolling window is prepared and scheduled: current, next ready, one more preparing.
    func replenishTail(sourceOffsetFrames: AVAudioFramePosition = 0) async {
        let planned = session.plannedItemIDs(depth: window.size)
        guard !planned.isEmpty else { return }
        let generation = session.queue.generation
        // A queue edit abandons every occurrence planned under the old generation, so a retry
        // deadline that expires afterwards cannot start work for a queue that no longer exists.
        preparationGate.cancelAll(except: generation)
        preparationGate.prune(keeping: generation, activeItems: Set(session.queue.items.map(\.id)))

        // The tail is tracked POSITIONALLY, not by item identity. A slot is legitimately scheduled
        // more than once — Repeat All wraps back to it, Repeat One plays it over and over — so
        // "have we scheduled this ID already?" would refuse to schedule the wrap and playback would
        // simply stop at the end of the queue.
        let audibleIndex = audiblePlayInstance
            .flatMap { instance in backend.scheduledSegments.firstIndex { $0.playInstance == instance } } ?? 0
        let alreadyOnTimeline = max(0, backend.scheduledSegments.count - audibleIndex)
        let needed = planned.count - alreadyOnTimeline
        guard needed > 0 else { return }
        let pending = Array(planned.suffix(needed))

        var toSchedule: [(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
                          generation: UInt64)] = []
        var identities: [GaplessQueueItemID: GaplessPreparationIdentity] = [:]
        for (offset, itemID) in pending.enumerated() {
            guard let item = session.queue.item(id: itemID) else { continue }
            let startOffset: AVAudioFramePosition = offset == 0 ? sourceOffsetFrames : 0
            let identity = preparationIdentity(for: itemID, songID: item.songID,
                                               generation: generation, offset: startOffset)
            // One occurrence, one attempt at a time — and none at all while a failure is still
            // cooling off or has been classified permanent.
            guard preparationGate.beginAttemptIfAllowed(identity) else { continue }

            var record = preparationRecords[itemID]
                ?? GaplessPreparationRecord(itemID: itemID, songID: item.songID,
                                            queueGeneration: generation, requestedAt: Date())
            session.markPreparing(itemID, generation: generation)
            do {
                var prepared = try await preparer.preparedTrack(item.songID)
                record.readyAt = Date()
                // A queue edit while this was in flight makes the result meaningless.
                guard session.queue.isCurrent(generation: generation) else {
                    staleResultCount += 1
                    preparationRecords[itemID] = record
                    // The queue moved on; this occurrence is abandoned rather than left `preparing`,
                    // which would block its replacement forever.
                    preparationGate.cancel(identity)
                    continue
                }
                // Only a batch that begins at the audible item can resume mid-track (restart/seek).
                if offset == 0, sourceOffsetFrames > 0, alreadyOnTimeline == 0 {
                    prepared = Self.offsetting(prepared, byFrames: sourceOffsetFrames)
                }
                session.markReady(itemID, renderFrames: prepared.renderFrames, generation: generation)
                preparationGate.recordReady(identity)
                toSchedule.append((prepared, itemID, generation))
                identities[itemID] = identity
                record.scheduledAt = Date()
                preparationRecords[itemID] = record
            } catch {
                record.failure = error.localizedDescription
                preparationRecords[itemID] = record
                session.markFailed(itemID, generation: generation)
                // Classified and rationed here; the gate logs the transition once rather than every
                // observation, so a permanent failure cannot flood the log.
                preparationGate.recordFailure(identity, error: error)
            }
        }

        guard !toSchedule.isEmpty else { return }
        scheduleBatch(toSchedule, identities: identities, generation: generation)
    }

    /// Hand a prepared batch to the backend and record what happened to each occurrence.
    private func scheduleBatch(_ batch: [(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
                                          generation: UInt64)],
                               identities: [GaplessQueueItemID: GaplessPreparationIdentity],
                               generation: UInt64) {
        do {
            let segments = try backend.schedule(batch)
            for segment in segments {
                session.markScheduled(segment.itemID, startFrame: segment.startFrame,
                                      generation: generation)
                if let identity = identities[segment.itemID] {
                    preparationGate.recordScheduled(identity)
                    // This slot has now begun a play; its next planned play is a new occurrence and
                    // gets its own attempt. Without this a Repeat All wrap could never be prepared.
                    occurrenceEpochs[segment.itemID] = (occurrenceEpochs[segment.itemID] ?? 0) + 1
                }
                scheduleGainEvent(for: segment)
            }
        } catch {
            log.error("scheduling failed: \(error.localizedDescription, privacy: .public)")
            for entry in batch {
                session.markFailed(entry.itemID, generation: generation)
                // Classified like any other failure, so a scheduling fault cannot spin either.
                if let identity = identities[entry.itemID] {
                    preparationGate.recordFailure(identity, error: error)
                }
            }
        }
    }

    /// Resume a prepared track from a source offset, preserving its trim range.
    /// Identity for a planned occurrence, stable across pump cycles that change nothing.
    private func preparationIdentity(for itemID: GaplessQueueItemID, songID: String,
                                     generation: UInt64,
                                     offset: AVAudioFramePosition) -> GaplessPreparationIdentity {
        GaplessPreparationIdentity(itemID: itemID, songID: songID, queueGeneration: generation,
                                   sourceStartOffsetFrames: offset,
                                   occurrenceEpoch: occurrenceEpochs[itemID] ?? 0)
    }

    /// Resume a prepared track from a source offset, preserving its trim range **and recording how
    /// far in it starts**, so elapsed time stays position-in-track rather than time-since-seek.
    private static func offsetting(_ track: GaplessPreparedTrack,
                                   byFrames offset: AVAudioFramePosition) -> GaplessPreparedTrack {
        let clamped = min(offset, AVAudioFramePosition(track.trim.frameCount))
        let remaining = AVAudioFrameCount(AVAudioFramePosition(track.trim.frameCount) - clamped)
        // The offset is applied INSIDE the trimmed range, so seeking never exposes encoder padding.
        let trim = GaplessTrim(startFrame: track.trim.startFrame + clamped,
                               frameCount: remaining, reason: track.trim.reason)
        let ratio = track.sourceSampleRate > 0
            ? Double(track.renderFrames) / Double(track.trim.frameCount) : 1
        return GaplessPreparedTrack(trackID: track.trackID, fileURL: track.fileURL, trim: trim,
                                    sourceSampleRate: track.sourceSampleRate,
                                    sourceChannelCount: track.sourceChannelCount,
                                    renderFrames: AVAudioFramePosition((Double(remaining) * ratio).rounded()),
                                    sourceStartOffsetFrames: track.sourceStartOffsetFrames
                                        + AVAudioFramePosition((Double(clamped) * ratio).rounded()))
    }

    /// Schedule the ReplayGain change for a segment at the frame it becomes audible.
    private func scheduleGainEvent(for segment: GaplessScheduledSegment) {
        guard session.markGainEventScheduled(segment.itemID) else { return }
        let resolved = GaplessReplayGainCalculator.resolve(
            replayGain: replayGains[segment.songID], settings: replayGainSettings)
        let event = GaplessGainEvent(trackID: segment.songID, boundaryFrame: segment.startFrame,
                                     gain: resolved.gain)
        backend.engine.gainStage.schedule(event)
    }

    // MARK: - Heartbeat

    /// Observe the render clock, advance the session, and keep the tail topped up.
    ///
    /// Boundaries come from the clock, so the window advances on **audible** progress rather than on
    /// scheduling callbacks — a track is "current" when it is being heard, not when it was queued.
    func tick() async {
        backend.observeBoundaries()
        let events = backend.drainBoundaryEvents()
        let clockFrame = backend.renderFrame

        // The backend's clock is authoritative; the session is advanced by the delta so its own
        // frame accounting stays in step with real rendered audio rather than with wall time.
        let delta = max(0, clockFrame - session.renderFrame)
        let live = events.filter { event in
            // A superseded tail must never move the session forward.
            guard backend.isCurrentTail(event.tailGeneration) else {
                staleResultCount += 1
                return false
            }
            return true
        }
        observedBoundaries.append(contentsOf: live)
        session.advance(renderedFrames: delta,
                        boundaries: live.map { ($0.itemID, $0.scheduledStartFrame) })

        if let latest = live.last { audiblePlayInstance = latest.playInstance }
        for event in live where preparationRecords[event.itemID]?.audibleAt == nil {
            preparationRecords[event.itemID]?.audibleAt = Date()
            // Recorded from the record that just became audible, so a stale queue generation, a
            // superseded tail or a replayed play instance cannot contribute: `live` has already been
            // filtered to the current tail, and a record only reaches here once.
            if let record = preparationRecords[event.itemID],
               record.queueGeneration == session.queue.generation {
                if let lead = record.preparationLeadTime { leadTimeStatistics.preparation.record(lead) }
                if let lead = record.schedulingLeadTime { leadTimeStatistics.scheduling.record(lead) }
            }
        }
        // Segments before the audible one describe audio that has already gone by; dropping them
        // keeps the timeline record bounded over a long run.
        if let instance = audiblePlayInstance { backend.pruneSegments(before: instance) }
        backend.engine.gainStage.advance(toRenderFrame: clockFrame)
        // Replenish on EVERY tick, not only after a boundary. Under `controlledWait` a slow item
        // lets the graph run dry, and no further boundary can fire while nothing is scheduled — so
        // a boundary-gated replenish would wait forever for an event that can only happen after it
        // has already run. The call is cheap: it returns immediately once the window is full.
        await replenishTail()
    }

    /// Report a deadline miss for an item that could not be ready in time.
    func recordDeadlineMiss(itemID: GaplessQueueItemID, songID: String,
                            lateByFrames: AVAudioFramePosition) {
        deadlineMisses.append(GaplessDeadlineMiss(itemID: itemID, songID: songID,
                                                  policy: deadlinePolicy,
                                                  lateByFrames: lateByFrames))
    }
}
