import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Checkpoint A: the minimal real-time buffer-scheduler proof.
///
/// The accepted root cause: *in the tested persistent `AVAudioPlayerNode` configuration,
/// `scheduleSegment` retains each supplied `AVAudioFile` and file descriptor until the player node
/// is stopped. This makes long uninterrupted sessions unbounded in both memory and descriptors.*
///
/// This suite proves the replacement substrate works before any transport is wired to it: buffers
/// are reused from a fixed pool, files are closed as soon as their audio is read, and transitions
/// are still sample-exact when checked against **captured audio** rather than against state.
@MainActor
struct GaplessBufferSchedulerTests {
    static let sampleRate = GaplessBufferFixtures.sampleRate

    /// A running engine plus scheduler, torn down cleanly.
    struct Rig {
        let engine: PersistentGaplessEngine
        let scheduler: GaplessBufferScheduler
        let directory: URL
    }

    static func makeRig(chunkFrames: AVAudioFrameCount = 4_096,
                        targetScheduledChunks: Int = 4,
                        recyclePoint: GaplessRecyclePoint = .dataConsumed,
                        poolHeadroom: Int = 2) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gbuf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let engine = PersistentGaplessEngine()
        let scheduler = GaplessBufferScheduler(player: engine.player,
                                               renderFormat: engine.renderFormat,
                                               chunkFrames: chunkFrames,
                                               targetScheduledChunks: targetScheduledChunks,
                                               recyclePoint: recyclePoint,
                                               poolHeadroom: poolHeadroom)
        return Rig(engine: engine, scheduler: scheduler, directory: directory)
    }

    /// Enqueue every URL in order, as prepared tracks resolved through the real trim policy.
    @discardableResult
    static func enqueue(_ rig: Rig, urls: [URL], startingItem: UInt64 = 0) throws -> [String] {
        var songIDs: [String] = []
        for (offset, url) in urls.enumerated() {
            let trackID = "t\(startingItem + UInt64(offset))"
            let track = try GaplessTrackPreparer.describe(trackID: trackID, fileURL: url,
                                                          renderSampleRate: sampleRate)
            try rig.scheduler.enqueue(track: track,
                                      itemID: GaplessQueueItemID(rawValue: startingItem + UInt64(offset)),
                                      generation: 1)
            songIDs.append(trackID)
        }
        return songIDs
    }

    /// Run the graph in real time until the scheduler has nothing left in flight, pumping at
    /// `pumpInterval`. Returns when playback has drained or the deadline passes.
    static func runToCompletion(_ rig: Rig, deadline: TimeInterval,
                                pumpInterval: Duration = .milliseconds(5)) async throws {
        rig.scheduler.pump()                       // preload before the first sample is asked for
        try rig.engine.engine.start()
        rig.engine.player.play()
        let end = Date().addingTimeInterval(deadline)
        while Date() < end {
            rig.scheduler.pump()
            if !rig.scheduler.hasPendingAudio, rig.scheduler.outstandingCallbackCount == 0 { break }
            try? await Task.sleep(for: pumpInterval)
        }
        // Let the last scheduled buffers actually reach the output before the capture is read.
        try? await Task.sleep(for: .milliseconds(300))
        rig.scheduler.pump()
    }

    static func teardown(_ rig: Rig) {
        rig.engine.player.stop()
        rig.engine.engine.stop()
        rig.scheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
        try? FileManager.default.removeItem(at: rig.directory)
    }

    // MARK: - Span analysis

    /// Which tone is actually present in the middle of each expected track span.
    ///
    /// `heardSequence` slides a fixed window across the whole capture, so a window that straddles a
    /// track boundary contains two tones and can report a third frequency that was never played —
    /// an artifact of the analysis, not of the audio. Sampling each track's interior removes that:
    /// it maps captured audio directly onto the span the scheduler says the track occupies, which is
    /// the claim under test.
    static func tonesInTrackInteriors(_ capture: GaplessRealTimeCapture, trackFrames: Int,
                                      trackCount: Int) -> [Double?] {
        let samples = capture.samples
        // The capture runs at the hardware rate, which is not the render rate. Scale scheduled
        // frames into capture frames rather than assuming one timebase, and analyse at the rate the
        // audio actually arrived at — a tone keeps its frequency in Hz through resampling, so the
        // Goertzel rate must be the capture's.
        let captureRate = capture.observedSampleRate > 0 ? capture.observedSampleRate : sampleRate
        let scale = captureRate / sampleRate
        let span = Int((Double(trackFrames) * scale).rounded())
        guard let origin = samples.firstIndex(where: { abs($0) > 0.01 }) else { return [] }
        var tones: [Double?] = []
        for index in 0..<trackCount {
            let start = origin + index * span
            let interiorStart = start + span / 4
            let interiorEnd = start + span * 3 / 4
            guard interiorEnd <= samples.count, interiorEnd > interiorStart else {
                tones.append(nil)
                continue
            }
            tones.append(GaplessRealTimeCapture.dominantFrequency(
                samples[interiorStart..<interiorEnd],
                frequencies: GaplessBufferFixtures.tones, sampleRate: captureRate))
        }
        return tones
    }

    /// The dominant frequency of the window centred on a track boundary, for showing what a
    /// straddling analysis window actually reports.
    static func toneAcrossBoundary(_ capture: GaplessRealTimeCapture, trackFrames: Int,
                                   boundaryIndex: Int, windowFrames: Int = 2_048) -> Double? {
        let samples = capture.samples
        let captureRate = capture.observedSampleRate > 0 ? capture.observedSampleRate : sampleRate
        let span = Int((Double(trackFrames) * captureRate / sampleRate).rounded())
        guard let origin = samples.firstIndex(where: { abs($0) > 0.01 }) else { return nil }
        let boundary = origin + boundaryIndex * span
        let start = max(0, boundary - windowFrames / 2)
        let end = min(samples.count, start + windowFrames)
        guard end > start else { return nil }
        return GaplessRealTimeCapture.dominantFrequency(
            samples[start..<end], frequencies: GaplessBufferFixtures.tones, sampleRate: captureRate)
    }

    // MARK: - Capture calibration

    /// What sample rate the capture tap actually runs at, and how many frames a known amount of
    /// audio occupies in it.
    ///
    /// The span analysis maps captured frames onto scheduled frames, so it is only valid if the two
    /// share a timebase. The mixer's output format is the hardware's, not the render format's, and
    /// assuming they match would silently stretch every span.
    @Test func captureTimebaseIsMeasuredNotAssumed() async throws {
        let rig = try Self.makeRig(chunkFrames: 4_096, targetScheduledChunks: 4)
        defer { Self.teardown(rig) }
        let frames = 8_820
        let urls = try GaplessBufferFixtures.makeAlbum(count: 4, frames: frames, in: rig.directory)
        try Self.enqueue(rig, urls: urls)

        let mixerRate = rig.engine.engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let outputRate = rig.engine.engine.outputNode.outputFormat(forBus: 0).sampleRate
        let capture = GaplessRealTimeCapture(engine: rig.engine)
        capture.start()
        try await Self.runToCompletion(rig, deadline: 12)
        capture.stop()

        let samples = capture.samples
        let first = samples.firstIndex(where: { abs($0) > 0.01 }) ?? 0
        let last = samples.lastIndex(where: { abs($0) > 0.01 }) ?? 0
        let audibleFrames = last - first + 1
        let scheduledFrames = 4 * frames
        print("""
            BUFCAL renderRate \(rig.engine.renderFormat.sampleRate)  mixerRate \(mixerRate)  \
            outputRate \(outputRate)  scheduled \(scheduledFrames) frames  \
            captured \(audibleFrames) audible frames  ratio \
            \(String(format: "%.4f", Double(audibleFrames) / Double(scheduledFrames)))  \
            totalCaptured \(samples.count)
            """)
        #expect(audibleFrames > 0)
    }

    // MARK: - Pool invariants

    /// The pool is fixed. Acquire/release cycles must not change its size, and a duplicated release
    /// must not hand the same buffer out twice — two chunks writing one buffer would corrupt audio
    /// that is already scheduled.
    @Test func poolIsFixedAndRejectsDoubleRelease() {
        let pool = GaplessBufferPool(capacity: 4, frameCapacity: 1_024,
                                     format: GaplessRenderFormat.standard)
        #expect(pool.availableCount == 4)
        var taken: [Int] = []
        while let ticket = pool.acquire() { taken.append(ticket.index) }
        #expect(taken.count == 4)
        #expect(pool.acquire() == nil, "the pool must starve rather than allocate")
        #expect(pool.inFlightCount == 4)

        #expect(pool.release(taken[0]) == true)
        #expect(pool.release(taken[0]) == false, "a repeated token must not re-issue the buffer")
        #expect(pool.availableCount == 1)
        #expect(pool.inFlightCount == 3)

        // Byte cost is a constant, not a function of how many cycles ran.
        #expect(pool.allocatedBytes == 4 * 1_024 * 2 * 4)
    }

    // MARK: - Chunk source

    /// The source reads exactly the trimmed range and lets go of the file the moment it is done —
    /// the descriptor bound depends on this, not on when the chunks finish playing.
    @Test func chunkSourceReadsTrimmedRangeThenClosesFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try GaplessBufferFixtures.makeAlbum(count: 1, frames: 10_000, in: directory)
        let track = try GaplessTrackPreparer.describe(trackID: "a", fileURL: urls[0],
                                                      renderSampleRate: Self.sampleRate)

        let source = try GaplessPCMChunkSource(track: track, itemID: GaplessQueueItemID(rawValue: 1),
                                               playInstance: GaplessPlayInstanceID(rawValue: 1),
                                               generation: 1,
                                               renderFormat: GaplessRenderFormat.standard)
        #expect(source.holdsOpenFile)
        let buffer = AVAudioPCMBuffer(pcmFormat: GaplessRenderFormat.standard, frameCapacity: 4_096)!

        var total: AVAudioFrameCount = 0
        var chunks = 0
        while true {
            let produced = try source.readChunk(into: buffer, maxFrames: 4_096)
            if produced == 0 { break }
            total += produced
            chunks += 1
            #expect(produced <= 4_096)
        }
        #expect(total == track.trim.frameCount, "read \(total) of \(track.trim.frameCount) trimmed frames")
        #expect(chunks == 3, "10000 frames at 4096 should be 3 chunks, got \(chunks)")
        #expect(source.isExhausted)
        #expect(!source.holdsOpenFile, "the file must be released as soon as its audio is read")
    }

    /// A source is closed after its audio is read even though its chunks are still scheduled. This
    /// is the property that decouples open files from playback length.
    @Test func filesCloseWhileTheirAudioIsStillScheduled() throws {
        let rig = try Self.makeRig(chunkFrames: 4_096, targetScheduledChunks: 4)
        defer { Self.teardown(rig) }
        // Two frames-worth of chunks each, so four tracks fit inside the scheduled window.
        let urls = try GaplessBufferFixtures.makeAlbum(count: 4, frames: 4_096, in: rig.directory)
        try Self.enqueue(rig, urls: urls)

        rig.scheduler.pump()
        #expect(rig.scheduler.inFlightChunks.count == 4)
        // Four chunks scheduled means all four one-chunk tracks have been fully read, so every file
        // is closed — while the node still holds all four buffers.
        #expect(rig.scheduler.openFileCount == 0,
                "still holding \(rig.scheduler.openFileCount) files")
    }

    // MARK: - Frame accounting

    /// Chunk descriptors must tile the timeline exactly: no inserted zero frames, no duplicates, no
    /// gaps, no overlap. Crossfade is disabled for this migration, so any overlap is a defect.
    @Test func chunkDescriptorsTileTheTimelineExactly() throws {
        let rig = try Self.makeRig(chunkFrames: 2_048, targetScheduledChunks: 64)
        defer { Self.teardown(rig) }
        let urls = try GaplessBufferFixtures.makeAlbum(count: 5, frames: 9_000, in: rig.directory)
        let songIDs = try Self.enqueue(rig, urls: urls)

        rig.scheduler.pump()                       // never started, so nothing recycles
        let chunks = rig.scheduler.inFlightChunks
        #expect(!chunks.isEmpty)

        var cursor: AVAudioFramePosition = 0
        var perTrack: [String: AVAudioFrameCount] = [:]
        for chunk in chunks {
            #expect(chunk.timelineStartFrame == cursor,
                    "chunk \(chunk.chunkIndex) of \(chunk.songID) starts at \(chunk.timelineStartFrame), expected \(cursor)")
            #expect(chunk.timelineFrameCount == chunk.sourceFrameCount)
            #expect(chunk.timelineFrameCount > 0)
            cursor = chunk.timelineEndFrame
            perTrack[chunk.songID, default: 0] += chunk.sourceFrameCount
        }
        // Every fully-scheduled track contributes exactly its trimmed length.
        for songID in songIDs where perTrack[songID] != nil {
            let scheduled = perTrack[songID]!
            let isComplete = chunks.contains { $0.songID == songID && $0.isFinalChunk }
            if isComplete { #expect(scheduled == 9_000, "\(songID) scheduled \(scheduled) frames") }
        }
        // First/final flags are set once each per completed track.
        for songID in songIDs {
            let firsts = chunks.filter { $0.songID == songID && $0.isFirstChunk }.count
            #expect(firsts <= 1, "\(songID) has \(firsts) first chunks")
        }
    }

    // MARK: - Recycle-point selection (captured audio)

    /// Which completion callback is safe to recycle at, decided by listening.
    ///
    /// A pool small enough to force reuse every few chunks, run against distinct per-track tones. If
    /// a buffer were refilled while the node could still read it, the captured audio would contain a
    /// tone out of order or a tone that never should have played there. State assertions cannot see
    /// that; the capture can.
    @Test(arguments: GaplessRecyclePoint.allCases)
    func recycleStressKeepsAudioIntact(point: GaplessRecyclePoint) async throws {
        // Deliberately tight: 4 in flight + 2 headroom, so every buffer is reused ~10 times.
        let rig = try Self.makeRig(chunkFrames: 4_096, targetScheduledChunks: 4, recyclePoint: point)
        defer { Self.teardown(rig) }
        let urls = try GaplessBufferFixtures.makeAlbum(count: 8, frames: 8_820, in: rig.directory)
        try Self.enqueue(rig, urls: urls)

        let capture = GaplessRealTimeCapture(engine: rig.engine)
        capture.start()
        try await Self.runToCompletion(rig, deadline: 12)
        capture.stop()

        let expected = (0..<8).map { GaplessBufferFixtures.tones[$0 % GaplessBufferFixtures.tones.count] }
        let interiors = Self.tonesInTrackInteriors(capture, trackFrames: 8_820, trackCount: 8)
        let gap = capture.longestSilenceSeconds(sampleRate: Self.sampleRate)
        print("""
            BUFRECYCLE \(point.rawValue): interiors \(interiors.map { $0.map(Int.init) ?? -1 }) \
            expected \(expected.map { Int($0) }) \
            gap \(String(format: "%.4f", gap))s \
            scheduled \(rig.scheduler.chunksScheduled) recycled \(rig.scheduler.chunksRecycled) \
            peakInFlight \(rig.scheduler.pool.peakInFlight) starvations \(rig.scheduler.poolStarvations)
            """)

        // Every track's own audio is present, in its own span. A buffer recycled while the node
        // could still read it would put the wrong tone inside one of these spans.
        #expect(interiors == expected.map { Optional($0) },
                "recycling at \(point.rawValue) altered the audio inside track spans")
        #expect(gap < 0.02, "recycling at \(point.rawValue) left a \(gap)s gap")
        #expect(rig.scheduler.pool.peakInFlight <= rig.scheduler.pool.capacity)
    }

    /// The same stress with **no pool headroom at all**: capacity equals the scheduled depth, so a
    /// buffer must come back before the next one can go out.
    ///
    /// This is what separates the three recycle points. A later recycle point returns buffers closer
    /// to the moment they finish playing, so the pump has less slack; if a point is too late, this
    /// configuration starves and the capture shows a gap. If a point is too *early*, the node is
    /// still reading a buffer the pump has already refilled, and the capture shows the wrong tone.
    /// Both failures are audible, and neither is visible in state.
    @Test(arguments: GaplessRecyclePoint.allCases)
    func recyclePointUnderMinimumPool(point: GaplessRecyclePoint) async throws {
        let rig = try Self.makeRig(chunkFrames: 4_096, targetScheduledChunks: 3,
                                   recyclePoint: point, poolHeadroom: 0)
        #expect(rig.scheduler.pool.capacity == 3, "no headroom: 3 scheduled, 3 buffers")
        defer { Self.teardown(rig) }
        let urls = try GaplessBufferFixtures.makeAlbum(count: 6, frames: 8_820, in: rig.directory)
        try Self.enqueue(rig, urls: urls)

        let capture = GaplessRealTimeCapture(engine: rig.engine)
        capture.start()
        try await Self.runToCompletion(rig, deadline: 12)
        capture.stop()

        let expected = (0..<6).map { GaplessBufferFixtures.tones[$0 % GaplessBufferFixtures.tones.count] }
        let interiors = Self.tonesInTrackInteriors(capture, trackFrames: 8_820, trackCount: 6)
        let gap = capture.longestSilenceSeconds(sampleRate: Self.sampleRate)
        print("""
            BUFTIGHT \(point.rawValue): interiors \(interiors.map { $0.map(Int.init) ?? -1 }) \
            gap \(String(format: "%.4f", gap))s starvations \(rig.scheduler.poolStarvations) \
            scheduled \(rig.scheduler.chunksScheduled) recycled \(rig.scheduler.chunksRecycled)
            """)
        #expect(interiors == expected.map { Optional($0) },
                "\(point.rawValue) corrupted audio under a minimum pool")
        #expect(gap < 0.02, "\(point.rawValue) starved into a \(gap)s gap")
    }

    // MARK: - Transition continuity (captured audio)

    /// The headline Checkpoint A result: 24 automatic transitions, all heard, in order, with no
    /// audible gap, and no player-node stop anywhere in the run.
    @Test func automaticTransitionsAreContinuousAndInOrder() async throws {
        let rig = try Self.makeRig(chunkFrames: 4_096, targetScheduledChunks: 4)
        defer { Self.teardown(rig) }
        let urls = try GaplessBufferFixtures.makeAlbum(count: 24, frames: 6_615, in: rig.directory)
        try Self.enqueue(rig, urls: urls)

        let capture = GaplessRealTimeCapture(engine: rig.engine)
        capture.start()
        try await Self.runToCompletion(rig, deadline: 20)
        capture.stop()

        let expected = (0..<24).map { GaplessBufferFixtures.tones[$0 % GaplessBufferFixtures.tones.count] }
        let interiors = Self.tonesInTrackInteriors(capture, trackFrames: 6_615, trackCount: 24)
        let slidingWindow = capture.heardSequence(frequencies: GaplessBufferFixtures.tones,
                                                  sampleRate: Self.sampleRate)
        let straddle = Self.toneAcrossBoundary(capture, trackFrames: 6_615, boundaryIndex: 7)
        let gap = capture.longestSilenceSeconds(sampleRate: Self.sampleRate)
        let expectedFrames = 24 * 6_615
        print("""
            BUFCONT transitions 24  interiors \(interiors.map { $0.map(Int.init) ?? -1 })  \
            gap \(String(format: "%.4f", gap))s  \
            timeline \(rig.scheduler.timelineCursor)/\(expectedFrames) frames  \
            chunks \(rig.scheduler.chunksScheduled) recycled \(rig.scheduler.chunksRecycled)  \
            openFiles \(rig.scheduler.openFileCount)  starvations \(rig.scheduler.poolStarvations)  \
            slidingWindowEntries \(slidingWindow.count) (expected \(expected.count))  \
            straddleWindowAtBoundary7 \(straddle.map(Int.init) ?? -1)
            """)

        #expect(interiors == expected.map { Optional($0) },
                "track spans contained \(interiors.map { $0.map(Int.init) ?? -1 })")
        #expect(gap < 0.02, "largest gap \(gap)s")
        // Exact frame accounting: every trimmed frame of every track reached the timeline, and not
        // one frame more.
        #expect(rig.scheduler.timelineCursor == AVAudioFramePosition(expectedFrames),
                "timeline \(rig.scheduler.timelineCursor), expected \(expectedFrames)")
        #expect(rig.scheduler.staleRecycles == 0)
    }
}
