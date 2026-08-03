import AVFoundation
import Foundation
import os.log

/// One item's journey from "we will need this" to "this is playing", timestamped.
///
/// Recorded so the preparation deadline can be *measured* rather than guessed: the only number that
/// matters is how much time was left between an item becoming ready and the moment it had to be
/// audible, and that cannot be reasoned about from code.
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
    /// Boundary events observed on the render clock, newest last.
    private(set) var observedBoundaries: [GaplessBoundaryEvent] = []

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
    func stop() {
        backend.stop()
        session.stop()
        observedBoundaries.removeAll()
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

        // The tail is tracked POSITIONALLY, not by item identity. A slot is legitimately scheduled
        // more than once — Repeat All wraps back to it, Repeat One plays it over and over — so
        // "have we scheduled this ID already?" would refuse to schedule the wrap and playback would
        // simply stop at the end of the queue.
        let audibleIndex = session.audibleItemID
            .flatMap { id in backend.scheduledSegments.firstIndex { $0.itemID == id } } ?? 0
        let alreadyOnTimeline = max(0, backend.scheduledSegments.count - audibleIndex)
        let needed = planned.count - alreadyOnTimeline
        guard needed > 0 else { return }
        let pending = Array(planned.suffix(needed))

        var toSchedule: [(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
                          generation: UInt64)] = []
        for (offset, itemID) in pending.enumerated() {
            guard let item = session.queue.item(id: itemID) else { continue }
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
                    continue
                }
                // Only a batch that begins at the audible item can resume mid-track (restart/seek).
                if offset == 0, sourceOffsetFrames > 0, alreadyOnTimeline == 0 {
                    prepared = Self.offsetting(prepared, byFrames: sourceOffsetFrames)
                }
                session.markReady(itemID, renderFrames: prepared.renderFrames, generation: generation)
                toSchedule.append((prepared, itemID, generation))
                record.scheduledAt = Date()
                preparationRecords[itemID] = record
            } catch {
                record.failure = error.localizedDescription
                preparationRecords[itemID] = record
                session.markFailed(itemID, generation: generation)
                log.error("preparation failed for \(item.songID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        guard !toSchedule.isEmpty else { return }
        do {
            let segments = try backend.schedule(toSchedule)
            for segment in segments {
                session.markScheduled(segment.itemID, startFrame: segment.startFrame,
                                      generation: generation)
                scheduleGainEvent(for: segment)
            }
        } catch {
            log.error("scheduling failed: \(error.localizedDescription, privacy: .public)")
            for entry in toSchedule { session.markFailed(entry.itemID, generation: generation) }
        }
    }

    /// Resume a prepared track from a source offset, preserving its trim range.
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
                                    renderFrames: AVAudioFramePosition((Double(remaining) * ratio).rounded()))
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

        for event in live where preparationRecords[event.itemID]?.audibleAt == nil {
            preparationRecords[event.itemID]?.audibleAt = Date()
        }
        backend.engine.gainStage.advance(toRenderFrame: clockFrame)
        if !live.isEmpty { await replenishTail() }
    }

    /// Report a deadline miss for an item that could not be ready in time.
    func recordDeadlineMiss(itemID: GaplessQueueItemID, songID: String,
                            lateByFrames: AVAudioFramePosition) {
        deadlineMisses.append(GaplessDeadlineMiss(itemID: itemID, songID: songID,
                                                  policy: deadlinePolicy,
                                                  lateByFrames: lateByFrames))
    }
}
