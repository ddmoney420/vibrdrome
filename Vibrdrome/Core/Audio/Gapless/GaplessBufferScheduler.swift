import AVFoundation
import Foundation
import os.log

/// When a pooled buffer may be handed back for reuse.
///
/// Not a preference — a measured property. `.dataConsumed` is the earliest point AVFoundation
/// offers, and reusing at the earliest safe point is what keeps the pool small; but reusing *before*
/// the node has finished reading the memory would corrupt audio that is already scheduled, which no
/// state assertion would catch. `GaplessBufferSchedulerTests.recycleStressKeepsAudioIntact` and
/// `recyclePointUnderMinimumPool` decide this by capturing output, not by reading documentation.
///
/// Measured: all three points keep captured audio intact, at pool capacity 6 and again with **no
/// headroom at all** (capacity == scheduled depth), with zero starvations in every case. So the
/// choice is not correctness but slack — `.dataConsumed` returns a buffer earliest and therefore
/// gives the pump the most time, which is why it is the default.
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

/// How long a converter lives relative to the tracks flowing through it.
///
/// Measured rather than assumed — see `GaplessConverterLifecycleTests`. The trade is real: a
/// converter reset between tracks makes each track's produced output exactly attributable, which is
/// what the timeline records require; carrying resampler state across a boundary would avoid a
/// prime/flush cycle but makes per-track attribution approximate at the sample level.
enum GaplessConverterLifecycle: String, Sendable, CaseIterable {
    /// A fresh `AVAudioConverter` for every track.
    case perTrack
    /// Reuse the converter *object* while the source format is unchanged, resetting its state
    /// between tracks; build a new one when the source format changes.
    case reuseWhileFormatMatches
}

/// Schedules a queue of tracks into a persistent `AVAudioPlayerNode` as reusable PCM buffers.
///
/// **Why this exists.** In the tested persistent `AVAudioPlayerNode` configuration,
/// `scheduleSegment` retains each supplied `AVAudioFile` and file descriptor until the player node
/// is stopped. That makes long uninterrupted sessions unbounded in both memory and descriptors.
/// PCM buffers scheduled with `scheduleBuffer` are released after consumption, so the substrate here
/// is: source file → bounded decode → optional bounded conversion → fixed buffer pool →
/// `scheduleBuffer`. The player node never receives an `AVAudioFile`.
///
/// **Produced frames are authoritative.** A track's timeline record is opened when its first chunk
/// is scheduled and *reconciled to actually produced output* when its last chunk is scheduled. A
/// declared length — `renderFrames`, or a rate-ratio estimate — is used only for planning. This is
/// what stops a truncated file, a short decode, or a resampler's priming and flush behaviour from
/// placing the next track at a frame where no audio was ever scheduled.
///
/// **What callbacks are for.** Recycling, and nothing else. Audible boundaries stay clock-driven:
/// a completion callback reports that the node finished with a buffer, which is not the instant the
/// next track became audible.
@MainActor
final class GaplessBufferScheduler {
    private let player: AVAudioPlayerNode
    let renderFormat: AVAudioFormat
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessBufferSched")

    let pool: GaplessBufferPool
    let inbox = GaplessRecycleInbox()
    /// Frames per chunk, in the **destination** format. Chosen by measurement.
    let chunkFrames: AVAudioFrameCount
    let targetScheduledChunks: Int
    let recyclePoint: GaplessRecyclePoint
    let converterLifecycle: GaplessConverterLifecycle

    private let instances = GaplessPlayInstanceAllocator()

    /// One track being streamed: its reader, its converter (when the formats differ), and the
    /// running total of output frames it has actually contributed.
    private final class ActiveSource {
        let source: GaplessPCMChunkSource
        var converter: GaplessPCMConverter?
        var producedOutputFrames: AVAudioFramePosition = 0
        var consumedSourceFrames: AVAudioFramePosition = 0
        var chunkIndex = 0
        /// Index into `segments` once the first chunk has been scheduled.
        var segmentIndex: Int?
        var timelineStart: AVAudioFramePosition = 0
        var failure: Error?

        init(source: GaplessPCMChunkSource, converter: GaplessPCMConverter?) {
            self.source = source
            self.converter = converter
        }

        var needsConversion: Bool { converter != nil }
        /// Finished when the reader has no more audio *and* any converter has drained its tail.
        var isDrained: Bool {
            guard source.isSourceExhausted else { return false }
            guard let converter else { return true }
            return converter.isFinished || converter.isCancelled
        }
    }

    private var sources: [ActiveSource] = []
    /// Converter kept for reuse under `.reuseWhileFormatMatches`, with the format it was built for.
    private var retainedConverter: (format: AVAudioFormat, converter: GaplessPCMConverter)?

    private(set) var inFlightChunks: [GaplessChunkDescriptor] = []
    /// Per-track timeline records, for clock-driven boundary observation.
    private(set) var segments: [GaplessScheduledSegment] = []

    /// Next free frame on the render timeline. Advanced only by frames actually produced.
    private(set) var timelineCursor: AVAudioFramePosition = 0
    private(set) var tailGeneration: UInt64 = 1

    // Diagnostics.
    private(set) var chunksScheduled = 0
    private(set) var chunksRecycled = 0
    private(set) var staleRecycles = 0
    private(set) var poolStarvations = 0
    private(set) var peakInFlightChunks = 0
    /// Tracks whose reconciled length differed from the planned estimate, and by how much.
    private(set) var reconciliations: [(songID: String, planned: AVAudioFramePosition,
                                        actual: AVAudioFramePosition)] = []
    /// Tracks that failed during decode or conversion, with the failure.
    private(set) var failures: [(songID: String, error: Error)] = []
    private(set) var converterRebuilds = 0
    /// How often the retained converter could actually be handed to the next track.
    private(set) var converterReuses = 0

    init(player: AVAudioPlayerNode, renderFormat: AVAudioFormat,
         chunkFrames: AVAudioFrameCount = 4_096,
         targetScheduledChunks: Int = 4,
         recyclePoint: GaplessRecyclePoint = .dataConsumed,
         converterLifecycle: GaplessConverterLifecycle = .reuseWhileFormatMatches,
         poolHeadroom: Int = 2) {
        self.player = player
        self.renderFormat = renderFormat
        self.chunkFrames = chunkFrames
        self.targetScheduledChunks = targetScheduledChunks
        self.recyclePoint = recyclePoint
        self.converterLifecycle = converterLifecycle
        pool = GaplessBufferPool(capacity: targetScheduledChunks + poolHeadroom,
                                 frameCapacity: chunkFrames, format: renderFormat)
        inbox.onDeposit = { [weak self] in
            Task { @MainActor [weak self] in self?.pump() }
        }
    }

    // MARK: - Enqueueing

    /// Add a prepared track to the streaming order.
    ///
    /// Opens the file and resolves conversion **now**, ahead of the boundary, so a format change
    /// cannot cost decode-and-converter-construction time at the moment the previous track ends.
    /// Produces no audio and creates no timeline record yet: the record is opened when the track's
    /// first chunk is actually scheduled, at the frame it actually lands on.
    @discardableResult
    func enqueue(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
                 generation: UInt64, startFrameOffset: AVAudioFrameCount = 0) throws
        -> GaplessScheduledSegment {
        let instance = instances.allocate()
        let source = try GaplessPCMChunkSource(track: track, itemID: itemID, playInstance: instance,
                                               generation: generation,
                                               startFrameOffset: startFrameOffset)
        var converter: GaplessPCMConverter?
        if source.processingFormat != renderFormat {
            do {
                converter = try makeConverter(for: source.processingFormat)
            } catch {
                source.close()
                throw error
            }
        }
        // The record is created now, with *planned* values, because the controller needs one segment
        // back per scheduled track. It is corrected twice afterwards: its start when the track's
        // first chunk actually lands, and its length when the track drains. Until the first chunk
        // lands the record is an estimate, which is why `materializedInstances` exists — boundary
        // observation must never fire on an estimated start.
        let planned = GaplessScheduledSegment(
            playInstance: instance, itemID: itemID, songID: track.trackID,
            generation: generation, tailGeneration: tailGeneration,
            startFrame: segments.last?.endFrame ?? timelineCursor,
            frameCount: max(0, track.renderFrames - AVAudioFramePosition(startFrameOffset)))
        let active = ActiveSource(source: source, converter: converter)
        active.segmentIndex = segments.count
        segments.append(planned)
        sources.append(active)
        return planned
    }

    /// Play instances whose segment record describes audio that has genuinely been scheduled.
    ///
    /// A record created at enqueue time carries a planned start derived from the previous track's
    /// *planned* length. If that track then reconciles shorter, the estimate is wrong — so a boundary
    /// must never be observed against it. Chunks are scheduled roughly 372 ms ahead of audibility, so
    /// a track is always materialised well before the clock reaches it.
    private(set) var materializedInstances: Set<GaplessPlayInstanceID> = []

    /// Build or reuse a converter according to the lifecycle policy.
    ///
    /// Reuse is gated on the retained converter not being held by any track still in the queue, not
    /// merely on the format matching. The preparation window keeps up to three tracks enqueued at
    /// once, so a format match alone would happily hand one `AVAudioConverter` to two tracks that
    /// are converting concurrently — their input would interleave into a single resampler state.
    /// That constraint is why reuse is often declined in practice; `converterReuses` records how
    /// often it was actually possible.
    private func makeConverter(for sourceFormat: AVAudioFormat) throws -> GaplessPCMConverter {
        if converterLifecycle == .reuseWhileFormatMatches,
           let retained = retainedConverter, retained.format == sourceFormat,
           !retained.converter.isCancelled,
           !sources.contains(where: { $0.converter === retained.converter }) {
            retained.converter.prepareForReuse()
            converterReuses += 1
            return retained.converter
        }
        converterRebuilds += 1
        let converter = try GaplessPCMConverter(sourceFormat: sourceFormat,
                                                destinationFormat: renderFormat,
                                                destinationChunkFrames: chunkFrames)
        if converterLifecycle == .reuseWhileFormatMatches {
            retainedConverter = (sourceFormat, converter)
        }
        return converter
    }

    var hasPendingAudio: Bool { sources.contains { !$0.isDrained } }
    var openFileCount: Int { sources.filter(\.source.holdsOpenFile).count }
    var liveSourceCount: Int { sources.count }
    var outstandingCallbackCount: Int { inFlightChunks.count }
    /// Converters currently attached to a queued track — the preparation-window bound.
    var activeConverterCount: Int { sources.filter(\.needsConversion).count }

    // MARK: - The pump

    /// Return finished buffers and top the schedule back up.
    func pump() {
        recycleFinishedBuffers()
        while inFlightChunks.count < targetScheduledChunks {
            guard let ticket = pool.acquire() else {
                poolStarvations += 1
                return
            }
            guard let descriptor = produceChunk(into: ticket.buffer) else {
                pool.release(ticket.index)
                return
            }
            scheduleChunk(descriptor, ticket: ticket)
        }
    }

    /// Fill one buffer from the head source, advancing to the next track when one drains.
    ///
    /// Crossing a track boundary inside this loop — rather than waiting for a caller to notice — is
    /// what makes the transition sample-exact: the last chunk of A and the first chunk of B are
    /// scheduled back to back with no gap frame and no zero fill between them.
    private func produceChunk(into buffer: AVAudioPCMBuffer) -> GaplessChunkDescriptor? {
        while let active = sources.first {
            if active.isDrained {
                finish(active)
                sources.removeFirst()
                continue
            }
            let sourceStart = active.source.track.trim.startFrame + active.consumedSourceFrames
            let wasFirst = active.chunkIndex == 0
            let produced: AVAudioFrameCount
            let sourceConsumed: AVAudioFramePosition

            do {
                (produced, sourceConsumed) = try fill(buffer, from: active)
            } catch {
                // A decode or conversion failure ends this track. The audible track is untouched:
                // this one has not been scheduled yet, and anything already scheduled for it stays
                // valid — the timeline is reconciled to what was actually produced.
                active.failure = error
                failures.append((active.source.track.trackID, error))
                log.error("""
                    chunk production failed for \(active.source.track.trackID, privacy: .public): \
                    \(error.localizedDescription, privacy: .public)
                    """)
                active.converter?.cancel()
                active.source.close()
                finish(active)
                sources.removeFirst()
                continue
            }

            guard produced > 0 else {
                finish(active)
                sources.removeFirst()
                continue
            }

            active.consumedSourceFrames += sourceConsumed
            if wasFirst {
                active.timelineStart = timelineCursor
                // Correct the planned start to the frame this track genuinely begins at, and only
                // now allow a boundary to be observed against it.
                if let index = active.segmentIndex, index < segments.count {
                    let existing = segments[index]
                    segments[index] = GaplessScheduledSegment(
                        playInstance: existing.playInstance, itemID: existing.itemID,
                        songID: existing.songID, generation: existing.generation,
                        tailGeneration: existing.tailGeneration, startFrame: timelineCursor,
                        frameCount: existing.frameCount)
                    materializedInstances.insert(existing.playInstance)
                }
            }
            let descriptor = GaplessChunkDescriptor(
                itemID: active.source.itemID, playInstance: active.source.playInstance,
                tailGeneration: tailGeneration, songID: active.source.track.trackID,
                sourceStartFrame: sourceStart,
                sourceFrameCount: AVAudioFrameCount(sourceConsumed),
                timelineStartFrame: timelineCursor, timelineFrameCount: produced,
                chunkIndex: active.chunkIndex, isFirstChunk: wasFirst,
                isFinalChunk: active.isDrained, wasConverted: active.needsConversion)
            active.chunkIndex += 1
            active.producedOutputFrames += AVAudioFramePosition(produced)
            timelineCursor += AVAudioFramePosition(produced)
            return descriptor
        }
        return nil
    }

    /// Fill one destination buffer from a source, converting if that source needs it.
    ///
    /// Returns both the output frames produced and the source frames consumed, because with a
    /// resampler in the path the two differ and the chunk record carries each separately.
    private func fill(_ buffer: AVAudioPCMBuffer, from active: ActiveSource) throws
        -> (produced: AVAudioFrameCount, sourceConsumed: AVAudioFramePosition) {
        guard let converter = active.converter else {
            let produced = try active.source.readSource(into: buffer, maxFrames: chunkFrames)
            return (produced, AVAudioFramePosition(produced))
        }
        let before = converter.consumedInputFrames
        let produced = try converter.convert(into: buffer) { [weak active] staging in
            guard let active else { return 0 }
            return try active.source.readSource(into: staging)
        }
        return (produced, converter.consumedInputFrames - before)
    }

    /// Reconcile a track's timeline record to the output it actually produced.
    ///
    /// This is the point where an estimate stops being used. If the file was truncated, if the
    /// decoder returned less than the container claimed, or if the resampler's priming and flush
    /// distributed frames differently, the record is corrected here — **before** the next track's
    /// first chunk lands, because that chunk is placed at `timelineCursor`, which only ever advanced
    /// by frames genuinely produced.
    private func finish(_ active: ActiveSource) {
        active.source.close()
        guard let index = active.segmentIndex, index < segments.count else { return }
        let existing = segments[index]
        let actual = active.producedOutputFrames
        // A track that produced nothing at all leaves no record: an empty span would be a phantom
        // segment, and a boundary against it would name a track the listener never heard.
        if actual == 0, !materializedInstances.contains(existing.playInstance) {
            segments.remove(at: index)
            for other in sources where (other.segmentIndex ?? 0) > index {
                other.segmentIndex = (other.segmentIndex ?? 0) - 1
            }
            return
        }
        if existing.frameCount != actual {
            reconciliations.append((existing.songID, existing.frameCount, actual))
            segments[index] = GaplessScheduledSegment(
                playInstance: existing.playInstance, itemID: existing.itemID,
                songID: existing.songID, generation: existing.generation,
                tailGeneration: existing.tailGeneration, startFrame: existing.startFrame,
                frameCount: actual)
        }
    }

    private func scheduleChunk(_ descriptor: GaplessChunkDescriptor,
                               ticket: (index: Int, buffer: AVAudioPCMBuffer)) {
        let token = GaplessRecycleToken(bufferIndex: ticket.index, chunkIndex: descriptor.chunkIndex,
                                        playInstance: descriptor.playInstance,
                                        tailGeneration: descriptor.tailGeneration)
        let inbox = self.inbox
        // The callback captures a token and the inbox. No buffer, no file, no converter, no decoder,
        // no track, no queue, no scheduler, no diagnostics — nothing that can own memory or grow
        // with the session.
        player.scheduleBuffer(ticket.buffer, at: nil, options: [],
                              completionCallbackType: recyclePoint.callbackType) { _ in
            inbox.deposit(token)
        }
        inFlightChunks.append(descriptor)
        chunksScheduled += 1
        peakInFlightChunks = max(peakInFlightChunks, inFlightChunks.count)
    }

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
    ///
    /// Every converter is cancelled first, so a conversion belonging to the discarded tail can never
    /// write into a buffer that has since been handed to another track.
    func resetAfterNodeStop(resumeTimelineFrame: AVAudioFramePosition) {
        tailGeneration += 1
        for active in sources {
            active.converter?.cancel()
            active.source.close()
        }
        sources.removeAll()
        retainedConverter = nil
        segments.removeAll()
        materializedInstances.removeAll()
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
        let dropped = segments.prefix(index).map(\.playInstance)
        segments.removeFirst(index)
        for playInstance in dropped { materializedInstances.remove(playInstance) }
        for active in sources {
            if let segmentIndex = active.segmentIndex { active.segmentIndex = segmentIndex - index }
        }
    }
}
