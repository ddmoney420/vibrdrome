import AVFoundation
import Foundation
import os.log

/// When a pooled buffer may be handed back for reuse.
///
/// Not a preference — a measured property. `.dataConsumed` is the earliest point AVFoundation
/// offers, and reusing at the earliest safe point is what keeps the pool small; but reusing *before*
/// the node has finished reading the memory would corrupt audio that is already scheduled, which no
/// state assertion would catch. `GaplessBufferSchedulerTests.recycleStress` decides this by
/// capturing output, not by reading documentation.
enum GaplessRecyclePoint: String, Sendable, CaseIterable {
    case dataConsumed
    case dataRendered
    case dataPlayedBack

    var callbackType: AVAudioPlayerNodeCompletionCallbackType {
        switch self {
        case .dataConsumed: return .dataConsumed
        case .dataRendered: return .dataRendered
        case .dataPlayedBack: return .dataPlayedBack
        }
    }
}

/// Schedules a queue of tracks into a persistent `AVAudioPlayerNode` as reusable PCM buffers.
///
/// **Why this exists.** In the tested persistent `AVAudioPlayerNode` configuration,
/// `scheduleSegment` retains each supplied `AVAudioFile` and file descriptor until the player node
/// is stopped. That makes long uninterrupted sessions unbounded in both memory and descriptors.
/// PCM buffers scheduled with `scheduleBuffer` are released after consumption, so the substrate here
/// is: source file → bounded decode → fixed buffer pool → `scheduleBuffer`. The player node never
/// receives an `AVAudioFile`.
///
/// **What is bounded.** Buffers are a fixed pool. Open files are bounded by how many chunk sources
/// still have audio left to read — at most the number of tracks with scheduled-but-unfinished
/// chunks, which is the preparation window, not the session. Chunk records are dropped as their
/// buffers come back.
///
/// **What callbacks are for.** Recycling, and nothing else. Audible boundaries stay clock-driven:
/// a completion callback reports that the node finished with a buffer, which is not the instant the
/// next track became audible. `segments` carries per-track timeline records for exactly that reason,
/// and the clock reads them.
@MainActor
final class GaplessBufferScheduler {
    private let player: AVAudioPlayerNode
    private let renderFormat: AVAudioFormat
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessBufferSched")

    let pool: GaplessBufferPool
    let inbox = GaplessRecycleInbox()
    /// Frames per chunk. Chosen by measurement — see `GaplessChunkSizeTests`.
    let chunkFrames: AVAudioFrameCount
    /// How many chunks to keep scheduled ahead of the render position.
    let targetScheduledChunks: Int
    let recyclePoint: GaplessRecyclePoint

    private let instances = GaplessPlayInstanceAllocator()
    /// Tracks with audio still to read, in play order. The head is the one being consumed.
    private var sources: [GaplessPCMChunkSource] = []
    /// Chunks handed to the node and not yet recycled.
    private(set) var inFlightChunks: [GaplessChunkDescriptor] = []
    /// Per-track timeline records, for clock-driven boundary observation.
    private(set) var segments: [GaplessScheduledSegment] = []

    /// Next free frame on the render timeline.
    private(set) var timelineCursor: AVAudioFramePosition = 0
    private(set) var tailGeneration: UInt64 = 1

    // Diagnostics.
    private(set) var chunksScheduled = 0
    private(set) var chunksRecycled = 0
    private(set) var staleRecycles = 0
    /// Times `pump` wanted a buffer and the pool had none — the underrun risk indicator.
    private(set) var poolStarvations = 0
    private(set) var peakInFlightChunks = 0

    init(player: AVAudioPlayerNode, renderFormat: AVAudioFormat,
         chunkFrames: AVAudioFrameCount = 4_096,
         targetScheduledChunks: Int = 4,
         recyclePoint: GaplessRecyclePoint = .dataRendered,
         poolHeadroom: Int = 2) {
        self.player = player
        self.renderFormat = renderFormat
        self.chunkFrames = chunkFrames
        self.targetScheduledChunks = targetScheduledChunks
        self.recyclePoint = recyclePoint
        pool = GaplessBufferPool(capacity: targetScheduledChunks + poolHeadroom,
                                 frameCapacity: chunkFrames, format: renderFormat)
        // Refill as soon as the node gives a buffer back, rather than waiting for the next
        // heartbeat. This is buffer lifecycle only; it publishes no boundary.
        inbox.onDeposit = { [weak self] in
            Task { @MainActor [weak self] in self?.pump() }
        }
    }

    // MARK: - Enqueueing

    /// Add a prepared track to the streaming order. Opens its file; produces no audio yet.
    @discardableResult
    func enqueue(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
                 generation: UInt64, startFrameOffset: AVAudioFrameCount = 0) throws
        -> GaplessScheduledSegment {
        let instance = instances.allocate()
        let source = try GaplessPCMChunkSource(track: track, itemID: itemID, playInstance: instance,
                                               generation: generation, renderFormat: renderFormat,
                                               startFrameOffset: startFrameOffset)
        // The timeline record is created up front, at the frame this track will actually begin, so
        // the clock can name the audible item before any of its chunks have been produced.
        let start = segments.last?.endFrame ?? timelineCursor
        let remaining = track.renderFrames - AVAudioFramePosition(startFrameOffset)
        let segment = GaplessScheduledSegment(
            playInstance: instance, itemID: itemID, songID: track.trackID,
            generation: generation, tailGeneration: tailGeneration,
            startFrame: start, frameCount: max(0, remaining))
        sources.append(source)
        segments.append(segment)
        return segment
    }

    /// Whether any enqueued track still has audio to schedule.
    var hasPendingAudio: Bool { sources.contains { !$0.isExhausted } }
    /// Sources still holding an open file — the descriptor bound.
    var openFileCount: Int { sources.filter(\.holdsOpenFile).count }
    var liveSourceCount: Int { sources.count }
    var outstandingCallbackCount: Int { inFlightChunks.count }

    // MARK: - The pump

    /// Return finished buffers and top the schedule back up.
    ///
    /// Safe to call at any cadence: it is idempotent when there is nothing to do, and it is the only
    /// place buffers move in either direction.
    func pump() {
        recycleFinishedBuffers()
        while inFlightChunks.count < targetScheduledChunks {
            guard let ticket = pool.acquire() else {
                poolStarvations += 1
                return
            }
            guard let descriptor = produceChunk(into: ticket.buffer) else {
                pool.release(ticket.index)
                return                                   // nothing left to schedule
            }
            scheduleChunk(descriptor, ticket: ticket)
        }
    }

    /// Fill one buffer from the head source, advancing to the next track when one runs out.
    ///
    /// Crossing a track boundary inside this loop — rather than waiting for a caller to notice — is
    /// what makes the transition sample-exact: the last chunk of A and the first chunk of B are
    /// scheduled back to back with no gap frame and no zero fill between them.
    private func produceChunk(into buffer: AVAudioPCMBuffer) -> GaplessChunkDescriptor? {
        while let source = sources.first {
            if source.isExhausted {
                source.close()
                sources.removeFirst()
                continue
            }
            let sourceStart = source.track.trim.startFrame + AVAudioFramePosition(source.framesRead)
            let chunkIndex = source.chunksProduced
            let wasFirst = source.framesRead == 0
            let produced: AVAudioFrameCount
            do {
                produced = try source.readChunk(into: buffer, maxFrames: chunkFrames)
            } catch {
                log.error("""
                    chunk read failed for \(source.track.trackID, privacy: .public): \
                    \(error.localizedDescription, privacy: .public)
                    """)
                source.close()
                sources.removeFirst()
                continue
            }
            guard produced > 0 else {
                source.close()
                sources.removeFirst()
                continue
            }
            let descriptor = GaplessChunkDescriptor(
                itemID: source.itemID, playInstance: source.playInstance,
                tailGeneration: tailGeneration, songID: source.track.trackID,
                sourceStartFrame: sourceStart, sourceFrameCount: produced,
                timelineStartFrame: timelineCursor,
                // No sample-rate conversion in this path; the converter stage sets these apart.
                timelineFrameCount: produced,
                chunkIndex: chunkIndex, isFirstChunk: wasFirst,
                isFinalChunk: source.isExhausted)
            timelineCursor += AVAudioFramePosition(produced)
            return descriptor
        }
        return nil
    }

    private func scheduleChunk(_ descriptor: GaplessChunkDescriptor,
                               ticket: (index: Int, buffer: AVAudioPCMBuffer)) {
        let token = GaplessRecycleToken(bufferIndex: ticket.index, chunkIndex: descriptor.chunkIndex,
                                        playInstance: descriptor.playInstance,
                                        tailGeneration: descriptor.tailGeneration)
        let inbox = self.inbox
        // The callback captures a token and the inbox. No buffer, no file, no decoder, no track, no
        // queue, no scheduler, no diagnostics — nothing that can own memory or grow with the
        // session.
        player.scheduleBuffer(ticket.buffer, at: nil, options: [],
                              completionCallbackType: recyclePoint.callbackType) { _ in
            inbox.deposit(token)
        }
        inFlightChunks.append(descriptor)
        chunksScheduled += 1
        peakInFlightChunks = max(peakInFlightChunks, inFlightChunks.count)
    }

    /// Move tokens the node has returned back into the pool.
    private func recycleFinishedBuffers() {
        for token in inbox.drain() {
            if token.tailGeneration != tailGeneration { staleRecycles += 1 }
            // Released regardless of staleness: the memory must come back even when the accounting
            // says the chunk belonged to a tail that has since been discarded. Losing it would
            // starve the pool permanently.
            pool.release(token.bufferIndex)
            if let index = inFlightChunks.firstIndex(where: {
                $0.playInstance == token.playInstance && $0.chunkIndex == token.chunkIndex
            }) {
                inFlightChunks.remove(at: index)
            }
            chunksRecycled += 1
        }
    }

    // MARK: - Teardown

    /// Discard everything not yet audible. Only valid after the caller has stopped the node, which
    /// is what makes reclaiming in-flight buffers safe — until then the node may still be reading
    /// them, and reusing one early would corrupt scheduled audio.
    func resetAfterNodeStop(resumeTimelineFrame: AVAudioFramePosition) {
        tailGeneration += 1
        for source in sources { source.close() }
        sources.removeAll()
        segments.removeAll()
        inFlightChunks.removeAll()
        inbox.reset()
        pool.reclaimAll()
        timelineCursor = resumeTimelineFrame
    }

    /// Drop timeline records for audio already played, so the record stays bounded across a long
    /// run. The audible segment and everything after it are kept.
    func pruneSegments(before instance: GaplessPlayInstanceID) {
        guard let index = segments.firstIndex(where: { $0.playInstance == instance }), index > 0
        else { return }
        segments.removeFirst(index)
    }
}
