import AVFoundation
import Foundation
import os.log

/// Something that happened at a real, audible point in the render timeline.
///
/// Every one of these is derived from frames actually rendered to the output — never from a download
/// finishing, a decode completing, or a buffer being accepted by the player node. That distinction
/// is the whole point: on this architecture the next track is decoded and scheduled long before it
/// is heard, so anything keyed off preparation would fire early and produce wrong metadata and
/// premature scrobbles.
enum GaplessPlaybackEvent: Sendable, Equatable {
    /// The item is now the audible one. Now Playing metadata switches here, and nowhere else.
    case becameAudible(itemID: GaplessQueueItemID, songID: String, atFrame: AVAudioFramePosition)
    /// The item finished rendering. `audibleFrames` is what was actually heard.
    case completed(itemID: GaplessQueueItemID, songID: String,
                   audibleFrames: AVAudioFramePosition, eligibleForScrobble: Bool)
    /// The queue ran out under Repeat Off.
    case queueEnded
}

/// Completion and scrobble accounting, reproducing the existing production policy.
///
/// Mapped from `AudioEngine.autoScrobbleIfNeeded` / `submitScrobbleIfNeeded`:
/// - Threshold is **half the effective duration, capped at 240 s**.
/// - Effective duration is the larger of the decoded and server-reported durations, because some
///   VBR/FLAC files under-report and would otherwise scrobble early (issue #90).
/// - **One eligible scrobble per play.** A repeat is a new play and may scrobble again; scheduling
///   or decoding a track is never a play.
struct GaplessCompletionPolicy: Sendable {
    /// Existing production cap.
    static let maximumThresholdSeconds: TimeInterval = 240
    /// Existing production fraction.
    static let thresholdFraction: Double = 0.5

    let sampleRate: Double

    /// Frames of audible playback required before a play counts.
    func scrobbleThresholdFrames(effectiveDurationSeconds: TimeInterval) -> AVAudioFramePosition {
        let seconds = min(Self.maximumThresholdSeconds,
                          effectiveDurationSeconds * Self.thresholdFraction)
        return AVAudioFramePosition((seconds * sampleRate).rounded())
    }

    /// Whether this play counts, given what was actually heard.
    func isEligible(audibleFrames: AVAudioFramePosition,
                    effectiveDurationSeconds: TimeInterval) -> Bool {
        guard effectiveDurationSeconds > 0 else { return false }
        return audibleFrames > scrobbleThresholdFrames(effectiveDurationSeconds: effectiveDurationSeconds)
    }
}

/// Drives a real playback session on the persistent engine: owns the queue, plans what to schedule,
/// and turns rendered frames into audible-boundary events.
///
/// The session never owns a second copy of the queue's *content* — it holds one
/// `GaplessPlaybackQueue`, which is the single authoritative model, and adds only derived scheduling
/// state. Transport actions mutate that model and then re-plan; they never reach into the engine's
/// scheduled tail directly.
///
/// **Cancellation strategy.** `AVAudioPlayerNode` cannot surgically remove one future buffer, so
/// invalidating the future means stopping the node and re-scheduling from the new starting point.
/// The session therefore separates the *audible* item from the *scheduled tail*: an edit that only
/// affects items after the audible one re-plans the tail, and an edit that changes what is audible
/// (skip, seek, replace) restarts from the new position. Both mark superseded items `.cancelled`,
/// which is what suppresses their gain event, their metadata boundary, and their scrobble
/// eligibility — a cancelled item never became audible, so it never counts as played.
@MainActor
final class GaplessPlaybackSession {
    private(set) var queue = GaplessPlaybackQueue()
    let completionPolicy: GaplessCompletionPolicy
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessSession")

    /// Frames rendered since the current schedule began — the session's clock.
    private(set) var renderFrame: AVAudioFramePosition = 0
    /// Highest boundary frame already turned into an audible event, so a boundary is applied once.
    private var lastAppliedBoundaryFrame: AVAudioFramePosition = -1
    private(set) var audibleItemID: GaplessQueueItemID?
    private(set) var isPlaying = false
    /// Emitted events, oldest first. Tests and the Now Playing bridge both read this.
    private(set) var events: [GaplessPlaybackEvent] = []

    /// Durations in seconds per song, used only for the scrobble threshold.
    var songDurations: [String: TimeInterval] = [:]

    /// Deterministic shuffle for tests; production leaves this nil and uses the system generator.
    var shuffleSeed: UInt64?
    private var seededGenerator: GaplessSeededRandomGenerator?
    /// Song IDs played recently, for the shuffle exclusion window.
    private(set) var recentlyPlayed: [String] = []

    init(sampleRate: Double = GaplessRenderFormat.sampleRate) {
        completionPolicy = GaplessCompletionPolicy(sampleRate: sampleRate)
    }

    // MARK: - Queue content

    func replaceQueue(songIDs: [String], replayGains: [String: ReplayGain?] = [:],
                      startIndex: Int = 0) {
        queue.replace(songIDs: songIDs, replayGains: replayGains, startIndex: startIndex)
        resetSchedule()
    }

    func setRepeatMode(_ mode: RepeatMode) {
        guard queue.repeatMode != mode else { return }
        queue.repeatMode = mode
        // Only the planned future is affected — the audible track keeps playing untouched.
        invalidateUpcoming()
    }

    func setShuffleEnabled(_ enabled: Bool) {
        guard queue.shuffleEnabled != enabled else { return }
        queue.shuffleEnabled = enabled
        invalidateUpcoming()
    }

    @discardableResult
    func playNext(songID: String, replayGain: ReplayGain? = nil) -> GaplessQueueItemID {
        let id = queue.playNext(songID: songID, replayGain: replayGain)
        invalidateUpcoming()
        return id
    }

    @discardableResult
    func addToQueue(songID: String, replayGain: ReplayGain? = nil) -> GaplessQueueItemID {
        let id = queue.append(songID: songID, replayGain: replayGain)
        // Appending past the window changes nothing that is already planned.
        if queue.index(of: id).map({ $0 <= queue.currentIndex + 2 }) == true { invalidateUpcoming() }
        return id
    }

    func remove(itemID: GaplessQueueItemID) {
        let wasAudible = itemID == audibleItemID
        queue.remove(id: itemID)
        if wasAudible {
            resetSchedule()
        } else {
            invalidateUpcoming()
        }
    }

    func move(itemID: GaplessQueueItemID, to destination: Int) {
        queue.move(id: itemID, to: destination)
        invalidateUpcoming()
    }

    func clearQueue() {
        queue.clear()
        resetSchedule()
    }

    /// Move the audible position without changing queue content — used when starting playback at a
    /// restored index, and by transport once a destination has been resolved.
    func setCurrentIndex(_ index: Int) {
        queue.setCurrentIndex(index)
    }

    // MARK: - Pipeline state (reported by the preparer and the engine)

    /// Record that preparation has started for an item, tagged with the generation it began under.
    /// Work from a superseded generation is ignored rather than applied to the new queue.
    func markPreparing(_ id: GaplessQueueItemID, generation: UInt64) {
        guard queue.isCurrent(generation: generation) else { return }
        queue.updateState(.preparing, for: id)
    }

    /// Record that an item is decoded and its exact frame count is known.
    func markReady(_ id: GaplessQueueItemID, renderFrames: AVAudioFramePosition, generation: UInt64) {
        guard queue.isCurrent(generation: generation) else { return }
        queue.update(id) { item in
            item.state = .ready
            item.renderFrames = renderFrames
        }
    }

    /// Record that an item's audio has been handed to the player node.
    func markScheduled(_ id: GaplessQueueItemID, startFrame: AVAudioFramePosition,
                       generation: UInt64) {
        guard queue.isCurrent(generation: generation) else { return }
        queue.update(id) { item in
            item.state = .scheduled
            item.scheduledStartFrame = startFrame
        }
    }

    /// Record that an item could not be prepared. Playback must skip it rather than stall.
    func markFailed(_ id: GaplessQueueItemID, generation: UInt64) {
        guard queue.isCurrent(generation: generation) else { return }
        queue.updateState(.failed, for: id)
    }

    /// Record that a ReplayGain event has been scheduled for an item, so it cannot be scheduled
    /// twice for the same play.
    @discardableResult
    func markGainEventScheduled(_ id: GaplessQueueItemID) -> Bool {
        guard let item = queue.item(id: id), !item.gainEventScheduled else { return false }
        queue.update(id) { $0.gainEventScheduled = true }
        return true
    }

    // MARK: - Planning

    /// The items that should be scheduled next, in play order, starting from the current index.
    ///
    /// `depth` matches the rolling preparation window (current + next ready + one preparing).
    /// Repeat One repeats the current slot; Repeat All wraps; Repeat Off stops at the end.
    func plannedItemIDs(depth: Int = 3) -> [GaplessQueueItemID] {
        guard !queue.isEmpty, queue.items.indices.contains(queue.currentIndex) else { return [] }
        var planned: [GaplessQueueItemID] = []
        var index = queue.currentIndex
        var plannedSongIDs: Set<String> = []

        for step in 0..<depth {
            guard queue.items.indices.contains(index) else { break }
            planned.append(queue.items[index].id)
            plannedSongIDs.insert(queue.items[index].songID)
            guard step < depth - 1 else { break }
            guard let next = nextIndex(after: index, plannedSongIDs: plannedSongIDs,
                                       manual: false) else { break }
            index = next
        }
        return planned
    }

    /// Next index under the current repeat/shuffle policy.
    func nextIndex(after index: Int, plannedSongIDs: Set<String> = [], manual: Bool) -> Int? {
        let chooser: () -> Int? = { [self] in shuffleNextIndex(from: index, planned: plannedSongIDs) }
        return manual
            ? GaplessTransportPolicy.nextIndexOnManualSkip(
                current: index, count: queue.count, repeatMode: queue.repeatMode,
                shuffleEnabled: queue.shuffleEnabled, shuffleNext: chooser)
            : GaplessTransportPolicy.nextIndexOnCompletion(
                current: index, count: queue.count, repeatMode: queue.repeatMode,
                shuffleEnabled: queue.shuffleEnabled, shuffleNext: chooser)
    }

    private func shuffleNextIndex(from index: Int, planned: Set<String>) -> Int? {
        let candidates = queue.items.enumerated().map { offset, item in
            GaplessShufflePolicy.Candidate(index: offset, songID: item.songID,
                                           artist: songArtists[item.songID].flatMap { $0 })
        }
        let lastArtist = queue.items.indices.contains(index)
            ? songArtists[queue.items[index].songID].flatMap { $0 } : nil
        if shuffleSeed != nil {
            if seededGenerator == nil { seededGenerator = GaplessSeededRandomGenerator(seed: shuffleSeed!) }
            var generator = seededGenerator!
            defer { seededGenerator = generator }
            return GaplessShufflePolicy.nextIndex(
                candidates: candidates, currentIndex: index, alreadyPlanned: planned,
                recentlyPlayed: recentlyPlayed, lastArtist: lastArtist, using: &generator)
        }
        var generator = SystemRandomNumberGenerator()
        return GaplessShufflePolicy.nextIndex(
            candidates: candidates, currentIndex: index, alreadyPlanned: planned,
            recentlyPlayed: recentlyPlayed, lastArtist: lastArtist, using: &generator)
    }

    /// Artists per song, for shuffle's different-artist preference.
    var songArtists: [String: String?] = [:]

    // MARK: - Transport

    func play() { isPlaying = true }
    func pause() { isPlaying = false }

    /// Stop: cancel the planned future and clear the audible item, leaving the queue intact and the
    /// session immediately reusable.
    func stop() {
        isPlaying = false
        resetSchedule()
    }

    /// Manual Next. Overrides Repeat One and never counts the skipped track unless it had already
    /// passed the threshold on its own.
    @discardableResult
    func skipToNext() -> GaplessQueueItemID? {
        finishAudibleItem(reason: .manualSkip)
        guard let destination = nextIndex(after: queue.currentIndex, manual: true) else {
            events.append(.queueEnded)
            resetSchedule()
            return nil
        }
        queue.setCurrentIndex(destination)
        resetSchedule()
        return queue.currentItem?.id
    }

    /// Manual Previous, using the production 3-second restart threshold.
    @discardableResult
    func skipToPrevious(elapsedSeconds: TimeInterval) -> GaplessTransportPolicy.PreviousDestination {
        let duration = queue.currentItem.flatMap { songDurations[$0.songID] } ?? 0
        let destination = GaplessTransportPolicy.previousDestination(
            currentIndex: queue.currentIndex, count: queue.count, elapsed: elapsedSeconds,
            duration: duration, isPlaying: isPlaying)
        finishAudibleItem(reason: .manualSkip)
        switch destination {
        case .restartCurrent:
            resetSchedule()
        case .item(let index):
            queue.setCurrentIndex(index)
            resetSchedule()
        }
        return destination
    }

    /// Seek within the audible track. Cancels the scheduled future and re-plans from the new
    /// position; the queue index is preserved and completion accounting restarts from what has
    /// actually been heard since the seek.
    func seek(toFrame frame: AVAudioFramePosition) {
        guard let audibleItemID else { return }
        queue.update(audibleItemID) { item in
            // Seeking backwards must not leave the item already past its scrobble threshold, and
            // seeking forwards must not credit unheard audio. Either way, what counts is what is
            // rendered from here on.
            item.audibleFrames = 0
            item.scrobbleSubmitted = false
        }
        seekOffsetFrames = frame
        resetSchedule(keepingAudibleItem: true)
    }

    /// Source frame the audible item resumes from after a seek.
    private(set) var seekOffsetFrames: AVAudioFramePosition = 0

    // MARK: - Render-driven progress

    /// Advance the session clock by frames actually rendered, emitting boundary events.
    ///
    /// This is the only place `audible`, `completed`, and scrobble eligibility are decided.
    func advance(renderedFrames: AVAudioFramePosition, boundaries: [(GaplessQueueItemID, AVAudioFramePosition)]) {
        renderFrame += renderedFrames
        for (itemID, startFrame) in boundaries.sorted(by: { $0.1 < $1.1 }) {
            guard startFrame <= renderFrame else { continue }
            // Keyed on the boundary, not on item identity: under Repeat One the *same* slot becomes
            // audible again at a new frame, and that is a genuinely new play — one that may earn its
            // own scrobble. Comparing item IDs alone would silently swallow every repeat.
            guard startFrame > lastAppliedBoundaryFrame else { continue }
            lastAppliedBoundaryFrame = startFrame
            makeAudible(itemID, atFrame: startFrame)
        }
        if let audibleItemID {
            queue.update(audibleItemID) { $0.audibleFrames = max(0, self.renderFrame - ($0.scheduledStartFrame ?? 0)) }
        }
    }

    private func makeAudible(_ itemID: GaplessQueueItemID, atFrame frame: AVAudioFramePosition) {
        finishAudibleItem(reason: .naturalEnd)
        guard let item = queue.item(id: itemID) else { return }
        audibleItemID = itemID
        queue.update(itemID) { entry in
            entry.state = .audible
            entry.scheduledStartFrame = frame
            entry.audibleFrames = 0
            // Becoming audible starts a NEW play. Under Repeat One that is the same slot again, and
            // a second full listen legitimately earns its own scrobble — carrying the previous
            // play's flag over would silently suppress it.
            entry.scrobbleSubmitted = false
        }
        if let index = queue.index(of: itemID) { queue.setCurrentIndex(index) }
        recentlyPlayed.append(item.songID)
        if recentlyPlayed.count > GaplessShufflePolicy.recentlyPlayedWindow {
            recentlyPlayed.removeFirst(recentlyPlayed.count - GaplessShufflePolicy.recentlyPlayedWindow)
        }
        events.append(.becameAudible(itemID: itemID, songID: item.songID, atFrame: frame))
    }

    enum FinishReason { case naturalEnd, manualSkip }

    /// Close out the audible item, deciding scrobble eligibility from audible frames alone.
    private func finishAudibleItem(reason: FinishReason) {
        guard let audibleItemID, let item = queue.item(id: audibleItemID) else { return }
        let duration = songDurations[item.songID] ?? 0
        let eligible = !item.scrobbleSubmitted
            && completionPolicy.isEligible(audibleFrames: item.audibleFrames,
                                           effectiveDurationSeconds: duration)
        queue.update(audibleItemID) { entry in
            entry.state = .completed
            if eligible { entry.scrobbleSubmitted = true }
        }
        events.append(.completed(itemID: audibleItemID, songID: item.songID,
                                 audibleFrames: item.audibleFrames, eligibleForScrobble: eligible))
        self.audibleItemID = nil
        _ = reason
    }

    // MARK: - Schedule invalidation

    /// Everything after the audible item is superseded — mark it cancelled so its gain event,
    /// metadata boundary and scrobble eligibility all go with it.
    private func invalidateUpcoming() {
        for item in queue.items where item.id != audibleItemID
        && (item.state == .scheduled || item.state == .ready || item.state == .preparing) {
            queue.updateState(.cancelled, for: item.id)
        }
    }

    /// Drop the whole planned schedule. `keepingAudibleItem` is used by seek, where the same item
    /// continues from a new position rather than being replaced.
    private func resetSchedule(keepingAudibleItem: Bool = false) {
        invalidateUpcoming()
        let keptID = keepingAudibleItem ? audibleItemID : nil
        if !keepingAudibleItem {
            audibleItemID = nil
            seekOffsetFrames = 0
        }
        renderFrame = 0
        lastAppliedBoundaryFrame = -1
        // Everything that has not already played is re-planned from scratch. Completed items keep
        // their state so a finished play is never counted twice.
        for item in queue.items where item.state != .completed && item.id != keptID {
            queue.update(item.id) { $0.resetForReplay() }
        }
    }

    // MARK: - Diagnostics

    #if DEBUG
    /// Snapshot for tests and later device diagnostics. Carries no URLs, tokens, or credentials —
    /// only queue identity, engine-derived state, and frame positions.
    struct Snapshot: Sendable, Equatable {
        let generation: UInt64
        let currentIndex: Int
        let repeatMode: String
        let shuffleEnabled: Bool
        let renderFrame: AVAudioFramePosition
        let audibleItem: GaplessQueueItemID?
        let states: [(GaplessQueueItemID, GaplessItemState)]

        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
            lhs.generation == rhs.generation && lhs.currentIndex == rhs.currentIndex
                && lhs.repeatMode == rhs.repeatMode && lhs.shuffleEnabled == rhs.shuffleEnabled
                && lhs.renderFrame == rhs.renderFrame && lhs.audibleItem == rhs.audibleItem
                && lhs.states.map(\.0) == rhs.states.map(\.0)
                && lhs.states.map(\.1) == rhs.states.map(\.1)
        }
    }

    var snapshot: Snapshot {
        Snapshot(generation: queue.generation, currentIndex: queue.currentIndex,
                 repeatMode: String(describing: queue.repeatMode),
                 shuffleEnabled: queue.shuffleEnabled, renderFrame: renderFrame,
                 audibleItem: audibleItemID,
                 states: queue.items.map { ($0.id, $0.state) })
    }
    #endif
}
