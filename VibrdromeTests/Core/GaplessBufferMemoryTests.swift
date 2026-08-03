import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Checkpoint A acceptance: does the buffer substrate actually plateau?
///
/// The file scheduler grew ~30 KB and one file descriptor for every schedule, without bound,
/// because the player node retained each `AVAudioFile` until it was stopped. The question here is
/// not whether buffers are tidier in principle but whether 1,000 transitions with a fresh file open
/// every time leave memory and descriptors flat.
@MainActor
struct GaplessBufferMemoryTests {
    static let sampleRate = GaplessBufferFixtures.sampleRate

    /// User + system CPU seconds consumed by this process.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    // MARK: - Chunk-size comparison

    struct ChunkSizeResult {
        let chunkFrames: AVAudioFrameCount
        let scheduleMedianMicroseconds: Double
        let callbacksPerSecond: Double
        let cpuPercent: Double
        let peakFootprintMB: Double
        let poolBytesKB: Double
        let peakInFlightBuffers: Int
        let starvations: Int
        let tailReplacementMilliseconds: Double
        let seekMilliseconds: Double
        let heardInOrder: Bool
        let largestGapSeconds: Double
    }

    /// Measure one chunk size end to end, including a tail replacement and a seek, against captured
    /// audio. Guessing a chunk size would trade an underrun risk against a callback-overhead risk
    /// without knowing either number.
    static func measureChunkSize(_ chunkFrames: AVAudioFrameCount) async throws -> ChunkSizeResult {
        let rig = try GaplessBufferSchedulerTests.makeRig(chunkFrames: chunkFrames,
                                                          targetScheduledChunks: 4)
        defer { GaplessBufferSchedulerTests.teardown(rig) }
        let trackCount = 8
        let urls = try GaplessBufferFixtures.makeAlbum(count: trackCount, frames: 22_050,
                                                       in: rig.directory)
        try GaplessBufferSchedulerTests.enqueue(rig, urls: urls)

        let capture = GaplessRealTimeCapture(engine: rig.engine)
        capture.start()

        var scheduleSamples: [Double] = []
        let cpuStart = cpuSeconds()
        let wallStart = Date()
        var peakFootprint = GaplessBufferFixtures.physFootprint()

        // Preload, timing the scheduling call itself.
        for _ in 0..<4 {
            let started = DispatchTime.now().uptimeNanoseconds
            rig.scheduler.pump()
            scheduleSamples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000)
        }
        try rig.engine.engine.start()
        rig.engine.player.play()

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            let started = DispatchTime.now().uptimeNanoseconds
            rig.scheduler.pump()
            scheduleSamples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000)
            peakFootprint = max(peakFootprint, GaplessBufferFixtures.physFootprint())
            if !rig.scheduler.hasPendingAudio, rig.scheduler.outstandingCallbackCount == 0 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        try? await Task.sleep(for: .milliseconds(250))
        capture.stop()
        let wallElapsed = Date().timeIntervalSince(wallStart)
        let cpuUsed = cpuSeconds() - cpuStart
        let callbacks = rig.scheduler.inbox.totalDeposits

        let expected = (0..<trackCount).map {
            GaplessBufferFixtures.tones[$0 % GaplessBufferFixtures.tones.count]
        }
        // Interior spans, not a sliding window: a window straddling a track boundary contains two
        // tones and can report a third that was never played.
        let interiors = GaplessBufferSchedulerTests.tonesInTrackInteriors(
            capture, trackFrames: 22_050, trackCount: trackCount)
        let gap = capture.longestSilenceSeconds(sampleRate: Self.sampleRate)

        // Tail replacement: stop the node, reclaim, re-enqueue from the audible position. This is
        // the mechanism Next/Previous/seek will use, so its cost belongs in the chunk-size choice.
        let tailStart = DispatchTime.now().uptimeNanoseconds
        rig.engine.player.stop()
        rig.scheduler.resetAfterNodeStop(resumeTimelineFrame: rig.scheduler.timelineCursor)
        try GaplessBufferSchedulerTests.enqueue(rig, urls: [urls[0]], startingItem: 900)
        rig.scheduler.pump()
        if rig.engine.engine.isRunning { rig.engine.player.play() }
        let tailMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - tailStart) / 1_000_000

        // Seek: rebuild from a frame offset inside the track.
        let seekStart = DispatchTime.now().uptimeNanoseconds
        rig.engine.player.stop()
        rig.scheduler.resetAfterNodeStop(resumeTimelineFrame: rig.scheduler.timelineCursor)
        let track = try GaplessTrackPreparer.describe(trackID: "seek", fileURL: urls[1],
                                                      renderSampleRate: Self.sampleRate)
        try rig.scheduler.enqueue(track: track, itemID: GaplessQueueItemID(rawValue: 901),
                                  generation: 1, startFrameOffset: 11_025)
        rig.scheduler.pump()
        if rig.engine.engine.isRunning { rig.engine.player.play() }
        let seekMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - seekStart) / 1_000_000

        let sorted = scheduleSamples.sorted()
        return ChunkSizeResult(
            chunkFrames: chunkFrames,
            scheduleMedianMicroseconds: sorted.isEmpty ? 0 : sorted[sorted.count / 2],
            callbacksPerSecond: wallElapsed > 0 ? Double(callbacks) / wallElapsed : 0,
            cpuPercent: wallElapsed > 0 ? cpuUsed / wallElapsed * 100 : 0,
            peakFootprintMB: Double(peakFootprint) / 1_048_576,
            poolBytesKB: Double(rig.scheduler.pool.allocatedBytes) / 1_024,
            peakInFlightBuffers: rig.scheduler.pool.peakInFlight,
            starvations: rig.scheduler.poolStarvations,
            tailReplacementMilliseconds: tailMilliseconds,
            seekMilliseconds: seekMilliseconds,
            heardInOrder: interiors == expected.map { Optional($0) },
            largestGapSeconds: gap)
    }

    /// The chunk-size matrix. Reports every candidate; the choice is made from the numbers.
    @Test func chunkSizeComparison() async throws {
        let candidates: [AVAudioFrameCount] = [2_048, 4_096, 8_192, 16_384, 32_768]
        // One discarded run first. The audio stack's one-time allocation and first-touch cost land
        // on whichever candidate runs first, and charging them to 2048 would misreport it by an
        // order of magnitude — that is a measurement artifact, not a property of the chunk size.
        _ = try await Self.measureChunkSize(8_192)
        var results: [ChunkSizeResult] = []
        for chunkFrames in candidates {
            let result = try await Self.measureChunkSize(chunkFrames)
            results.append(result)
            print(String(format: """
                CHUNK %6d  sched %7.1f us  cb/s %6.1f  cpu %5.1f%%  peakFP %7.1f MB  \
                pool %7.1f KB  peakBuf %d  starv %d  tail %6.2f ms  seek %6.2f ms  \
                order %@  gap %.4f s
                """,
                Int(result.chunkFrames), result.scheduleMedianMicroseconds,
                result.callbacksPerSecond, result.cpuPercent, result.peakFootprintMB,
                result.poolBytesKB, result.peakInFlightBuffers, result.starvations,
                result.tailReplacementMilliseconds, result.seekMilliseconds,
                (result.heardInOrder ? "OK" : "WRONG") as NSString, result.largestGapSeconds))
        }
        // Every candidate must at least be correct; the choice between them is cost, not validity.
        for result in results {
            #expect(result.heardInOrder, "chunk \(result.chunkFrames) played out of order")
            #expect(result.largestGapSeconds < 0.02,
                    "chunk \(result.chunkFrames) left a \(result.largestGapSeconds)s gap")
        }
    }

    // MARK: - 1,000-transition memory and descriptor acceptance

    struct MemorySample {
        let transitions: Int
        let footprintMB: Double
        let residentMB: Double
        let dirtyMB: Double
        let liveHeapMB: Double
        let descriptors: Int
        let liveAudioFiles: Int
        let liveSources: Int
        let poolAvailable: Int
        let poolInFlight: Int
        let inFlightChunks: Int
        let segments: Int
    }

    /// 1,000 transitions, a fresh `AVAudioFile` for every single one, a queue far larger than any
    /// object cache, and no player-node stop anywhere in the run.
    ///
    /// Enqueueing is done on demand — at most three tracks ahead — because that is what the
    /// preparation window does in production. Enqueueing all 1,000 up front would open 1,000 files
    /// at once and prove nothing about the steady state.
    @Test func thousandTransitionsPlateauInMemoryAndDescriptors() async throws {
        let warmUpTransitions = 100
        let windowSize = 200
        let windows = 5
        let totalTransitions = warmUpTransitions + windowSize * windows

        let rig = try GaplessBufferSchedulerTests.makeRig(chunkFrames: 4_096,
                                                          targetScheduledChunks: 4)
        defer { GaplessBufferSchedulerTests.teardown(rig) }
        // 64 distinct sources: larger than the old 6-entry file cache, and larger than any cache it
        // would be safe to hold open, so a cache could not mask the result.
        let urls = try GaplessBufferFixtures.makeAlbum(count: 64, frames: 4_410, in: rig.directory)

        var enqueued = 0
        func topUp() throws {
            while rig.scheduler.liveSourceCount < 3, enqueued < totalTransitions {
                let track = try GaplessTrackPreparer.describe(
                    trackID: "m\(enqueued)", fileURL: urls[enqueued % urls.count],
                    renderSampleRate: Self.sampleRate)
                try rig.scheduler.enqueue(track: track,
                                          itemID: GaplessQueueItemID(rawValue: UInt64(enqueued)),
                                          generation: 1)
                enqueued += 1
            }
        }

        try topUp()
        rig.scheduler.pump()
        try rig.engine.engine.start()
        rig.engine.player.play()

        func sample(_ transitions: Int) -> MemorySample {
            let memory = GaplessBufferFixtures.residentAndDirty()
            return MemorySample(
                transitions: transitions,
                footprintMB: Double(GaplessBufferFixtures.physFootprint()) / 1_048_576,
                residentMB: Double(memory.resident) / 1_048_576,
                dirtyMB: Double(memory.dirty) / 1_048_576,
                liveHeapMB: Double(GaplessBufferFixtures.liveHeapBytes()) / 1_048_576,
                descriptors: GaplessBufferFixtures.openFileDescriptorCount(),
                liveAudioFiles: GaplessPCMChunkSource.liveFileCount,
                liveSources: rig.scheduler.liveSourceCount,
                poolAvailable: rig.scheduler.pool.availableCount,
                poolInFlight: rig.scheduler.pool.inFlightCount,
                inFlightChunks: rig.scheduler.outstandingCallbackCount,
                segments: rig.scheduler.segments.count)
        }

        var baseline: MemorySample?
        var samples: [MemorySample] = []
        var nextWindowBoundary = warmUpTransitions + windowSize
        var peakDescriptors = 0
        var peakLiveFiles = 0
        var deadlineMisses = 0

        let hardDeadline = Date().addingTimeInterval(400)
        while Date() < hardDeadline {
            try topUp()
            rig.scheduler.pump()
            // Segment records are pruned the way the controller prunes them, so the timeline record
            // cannot masquerade as a plateau failure.
            if rig.scheduler.segments.count > 16,
               let anchor = rig.scheduler.segments.dropLast(8).last {
                rig.scheduler.pruneSegments(before: anchor.playInstance)
            }
            if rig.scheduler.poolStarvations > 0 { deadlineMisses = rig.scheduler.poolStarvations }
            peakDescriptors = max(peakDescriptors, GaplessBufferFixtures.openFileDescriptorCount())
            peakLiveFiles = max(peakLiveFiles, GaplessPCMChunkSource.liveFileCount)

            // "Transitions" here is tracks fully consumed, which is `enqueued` minus what is still
            // live in the scheduler.
            let consumed = enqueued - rig.scheduler.liveSourceCount
            if baseline == nil, consumed >= warmUpTransitions { baseline = sample(consumed) }
            if baseline != nil, consumed >= nextWindowBoundary, samples.count < windows {
                samples.append(sample(consumed))
                nextWindowBoundary += windowSize
            }
            if enqueued >= totalTransitions, !rig.scheduler.hasPendingAudio,
               rig.scheduler.outstandingCallbackCount == 0 { break }
            try? await Task.sleep(for: .milliseconds(4))
        }

        let final = sample(enqueued - rig.scheduler.liveSourceCount)
        let base = try #require(baseline, "warm-up never completed")

        print("""
            BUFMEM baseline  tx \(base.transitions)  fp \(String(format: "%.1f", base.footprintMB)) MB  \
            rss \(String(format: "%.1f", base.residentMB))  dirty \(String(format: "%.1f", base.dirtyMB))  \
            heap \(String(format: "%.1f", base.liveHeapMB))  fd \(base.descriptors)  \
            files \(base.liveAudioFiles)  pool \(base.poolAvailable)/\(base.poolInFlight)  \
            chunks \(base.inFlightChunks)  segs \(base.segments)
            """)
        for entry in samples + [final] {
            print("""
                BUFMEM window    tx \(entry.transitions)  fp \(String(format: "%.1f", entry.footprintMB)) MB  \
                rss \(String(format: "%.1f", entry.residentMB))  dirty \(String(format: "%.1f", entry.dirtyMB))  \
                heap \(String(format: "%.1f", entry.liveHeapMB))  fd \(entry.descriptors)  \
                files \(entry.liveAudioFiles)  pool \(entry.poolAvailable)/\(entry.poolInFlight)  \
                chunks \(entry.inFlightChunks)  segs \(entry.segments)
                """)
        }

        let growthMB = final.footprintMB - base.footprintMB
        let measuredTransitions = final.transitions - base.transitions
        let perTransitionKB = measuredTransitions > 0
            ? growthMB * 1_024 / Double(measuredTransitions) : 0
        let descriptorGrowth = final.descriptors - base.descriptors

        // Stop and cleanup: memory must return near warmed idle rather than merely stop climbing.
        rig.engine.player.stop()
        rig.engine.engine.stop()
        rig.scheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
        try? await Task.sleep(for: .seconds(2))
        let afterStop = sample(final.transitions)

        print("""
            BUFMEM RESULT  transitions \(measuredTransitions)  \
            growth \(String(format: "%.2f", growthMB)) MB  \
            \(String(format: "%.2f", perTransitionKB)) KB/tx  \
            fdΔ \(descriptorGrowth)  peakFd \(peakDescriptors)  peakFiles \(peakLiveFiles)  \
            starvations \(deadlineMisses)  chunksScheduled \(rig.scheduler.chunksScheduled)  \
            recycled \(rig.scheduler.chunksRecycled)  \
            afterStop fp \(String(format: "%.1f", afterStop.footprintMB)) MB \
            fd \(afterStop.descriptors) files \(afterStop.liveAudioFiles)
            """)

        #expect(measuredTransitions >= 900, "only \(measuredTransitions) measured transitions")
        // The acceptance gate: memory plateaus below the existing 40 MB tolerance...
        #expect(growthMB < 40, "footprint grew \(growthMB) MB over \(measuredTransitions) transitions")
        // ...and descriptors stay flat rather than tracking transitions.
        #expect(descriptorGrowth <= 8, "descriptors grew by \(descriptorGrowth)")
        #expect(peakLiveFiles <= 4, "live AVAudioFile count peaked at \(peakLiveFiles)")
        // Buffers stay at the declared pool capacity, whatever the session length.
        #expect(rig.scheduler.pool.peakInFlight <= rig.scheduler.pool.capacity)
        #expect(afterStop.liveAudioFiles == 0, "\(afterStop.liveAudioFiles) files still open after stop")
        // Outstanding callbacks track the scheduled window, not the number of transitions.
        #expect(rig.scheduler.peakInFlightChunks <= rig.scheduler.targetScheduledChunks)
    }
}
