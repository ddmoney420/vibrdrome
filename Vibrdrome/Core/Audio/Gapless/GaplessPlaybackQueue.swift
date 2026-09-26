import AVFoundation
import Foundation

/// Identity of one *slot* in the queue, distinct from the song in it.
///
/// A queue can legitimately contain the same song twice (an album with a reprise, a playlist that
/// repeats a track, "Play Next" on something already queued). Keying scheduling state by song ID
/// would make those slots indistinguishable, so every slot gets its own identity that survives
/// reordering and is never reused.
struct GaplessQueueItemID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: UInt64
    var description: String { "q\(rawValue)" }
}

/// Where one queue item has got to in the scheduling pipeline.
///
/// These are *derived* states owned by the engine, not queue content. The queue itself (order,
/// current index, repeat, shuffle) is owned by the application — see `GaplessPlaybackQueue`.
enum GaplessItemState: String, Sendable, Equatable, CaseIterable {
    /// In the queue, nothing started.
    case pending
    /// Bytes being fetched / decoded.
    case preparing
    /// Local file open, exact frame range known — safe to schedule.
    case ready
    /// Handed to the player node; audio is queued but not yet heard.
    case scheduled
    /// Currently being rendered to the output. Exactly one item is audible at a time.
    case audible
    /// Finished rendering. Completion and scrobble eligibility are decided from audible frames.
    case completed
    /// Superseded by a queue edit before it became audible.
    case cancelled
    /// Could not be prepared; playback must skip it rather than stall.
    case failed
}

/// A queue slot plus the engine-owned state for it.
struct GaplessQueueItem: Sendable, Equatable, Identifiable {
    let id: GaplessQueueItemID
    let songID: String
    /// Server ReplayGain metadata, carried so the gain event can be resolved at prepare time.
    var replayGain: ReplayGain?
    var state: GaplessItemState = .pending
    /// Render frame at which this item becomes audible, once scheduled.
    var scheduledStartFrame: AVAudioFramePosition?
    /// Frames of this item actually rendered — the only basis for completion and scrobbling.
    var audibleFrames: AVAudioFramePosition = 0
    /// Total render frames the item contributes, known once prepared.
    var renderFrames: AVAudioFramePosition?
    /// Whether a scrobble has already been counted for the current play of this slot.
    var scrobbleSubmitted = false
    /// Whether a ReplayGain event has been scheduled for the current play of this slot.
    var gainEventScheduled = false

    /// Reset the per-play state so a repeat is a genuinely new play, not a continuation.
    mutating func resetForReplay() {
        state = .pending
        scheduledStartFrame = nil
        audibleFrames = 0
        scrobbleSubmitted = false
        gainEventScheduled = false
    }
}

/// The authoritative playback queue.
///
/// **Source of truth.** Queue *content* — order, current index, repeat mode, shuffle flag — belongs
/// to the application (today `AudioEngine`, which the UI already binds to). This type is the single
/// place that content is mirrored into the engine, and it adds only *derived* per-item scheduling
/// state. There is deliberately no second, hidden playback queue: every mutation goes through here,
/// so the engine cannot drift from what the user sees.
///
/// **Generation.** Every structural change bumps `generation`. Asynchronous work — a download, a
/// decode, a scheduling callback — carries the generation it started under, and anything arriving
/// from an older generation is discarded. This is what makes "replace the queue while three tracks
/// are being prepared" safe without cancelling work that is still valid.
struct GaplessPlaybackQueue: Sendable {
    private(set) var items: [GaplessQueueItem] = []
    private(set) var currentIndex: Int = 0
    /// Monotonically increasing; bumped on every structural change.
    private(set) var generation: UInt64 = 0
    var repeatMode: RepeatMode = .off
    var shuffleEnabled = false

    private var nextItemRawID: UInt64 = 1

    init() {}

    // MARK: - Identity

    private mutating func makeID() -> GaplessQueueItemID {
        defer { nextItemRawID += 1 }
        return GaplessQueueItemID(rawValue: nextItemRawID)
    }

    private mutating func makeItem(songID: String, replayGain: ReplayGain?) -> GaplessQueueItem {
        GaplessQueueItem(id: makeID(), songID: songID, replayGain: replayGain)
    }

    // MARK: - Reading

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }
    var currentItem: GaplessQueueItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    func item(id: GaplessQueueItemID) -> GaplessQueueItem? { items.first { $0.id == id } }
    func index(of id: GaplessQueueItemID) -> Int? { items.firstIndex { $0.id == id } }

    /// True when work tagged with `generation` still describes the live queue.
    func isCurrent(generation candidate: UInt64) -> Bool { candidate == generation }

    // MARK: - Structural changes (each bumps the generation)

    /// Replace the entire queue — a new album, playlist, search result, or restored session.
    mutating func replace(songIDs: [String], replayGains: [String: ReplayGain?] = [:],
                          startIndex: Int = 0) {
        items = songIDs.map { makeItem(songID: $0, replayGain: replayGains[$0].flatMap { $0 }) }
        currentIndex = items.indices.contains(startIndex) ? startIndex : 0
        generation += 1
    }

    /// Insert immediately after the current item — "Play Next".
    @discardableResult
    mutating func playNext(songID: String, replayGain: ReplayGain? = nil) -> GaplessQueueItemID {
        let item = makeItem(songID: songID, replayGain: replayGain)
        let insertAt = items.isEmpty ? 0 : min(currentIndex + 1, items.count)
        items.insert(item, at: insertAt)
        generation += 1
        return item.id
    }

    /// Append to the end — "Add to Queue".
    @discardableResult
    mutating func append(songID: String, replayGain: ReplayGain? = nil) -> GaplessQueueItemID {
        let item = makeItem(songID: songID, replayGain: replayGain)
        items.append(item)
        generation += 1
        return item.id
    }

    /// Remove a slot. Keeps the *same item* audible where possible by tracking identity rather than
    /// index — removing an earlier item must not silently change what is playing.
    mutating func remove(id: GaplessQueueItemID) {
        guard let removeAt = index(of: id) else { return }
        let audibleID = currentItem?.id
        items.remove(at: removeAt)
        if let audibleID, let stillThere = index(of: audibleID) {
            currentIndex = stillThere
        } else {
            // The audible item itself was removed: stay at the same position, which is now the
            // following item, clamped to the queue.
            currentIndex = min(removeAt, max(0, items.count - 1))
        }
        generation += 1
    }

    /// Reorder, preserving which item is audible.
    mutating func move(id: GaplessQueueItemID, to destination: Int) {
        guard let from = index(of: id), items.indices.contains(destination) else { return }
        let audibleID = currentItem?.id
        let item = items.remove(at: from)
        items.insert(item, at: min(destination, items.count))
        if let audibleID, let stillThere = index(of: audibleID) { currentIndex = stillThere }
        generation += 1
    }

    mutating func clear() {
        items.removeAll()
        currentIndex = 0
        generation += 1
    }

    /// Move the audible position without changing content. Does **not** bump the generation:
    /// advancing through the queue is not a structural change, and bumping here would needlessly
    /// invalidate preparation work that is still correct.
    mutating func setCurrentIndex(_ index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
    }

    // MARK: - Per-item state

    mutating func updateState(_ state: GaplessItemState, for id: GaplessQueueItemID) {
        guard let index = index(of: id) else { return }
        items[index].state = state
    }

    mutating func update(_ id: GaplessQueueItemID, _ body: (inout GaplessQueueItem) -> Void) {
        guard let index = index(of: id) else { return }
        body(&items[index])
    }

    /// Reset every item that is not the audible one — used when a transport action invalidates the
    /// planned future.
    mutating func resetUpcomingState() {
        for index in items.indices where index != currentIndex {
            items[index].resetForReplay()
        }
    }
}
