import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Checkpoint C: the buffer substrate driven through the real playback controller.
///
/// Everything up to here exercised `GaplessBufferScheduler` directly. These run it where it will
/// actually live — behind `GaplessRealTimeBackend`, under `GaplessPlaybackController`, with the
/// session, the preparation window, repeat modes and transport all in the path.
///
/// Serialised: these drive real `AVAudioEngine` instances, and overlapping engines destabilise the
/// test process.
@Suite(.serialized)
@MainActor
struct GaplessBufferIntegrationTests {
    static let sampleRate = GaplessBufferFixtures.sampleRate

    struct Rig {
        let engine: PersistentGaplessEngine
        let backend: GaplessRealTimeBackend
        let controller: GaplessPlaybackController
        let session: GaplessPlaybackSession
        let directory: URL
    }

    /// A controller wired to the production backend, over `count` distinct local tracks.
    static func makeRig(trackCount: Int, frames: Int = 6_615,
                        sampleRate rate: Double = sampleRate,
                        channels: UInt16 = 2) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gci-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var files: [String: URL] = [:]
        var songIDs: [String] = []
        for index in 0..<trackCount {
            let url = directory.appendingPathComponent("i\(index).wav")
            try GaplessBufferFixtures.writeWav(
                url: url,
                frequency: GaplessBufferFixtures.tones[index % GaplessBufferFixtures.tones.count],
                frames: frames, sampleRate: rate, channelCount: channels)
            files["s\(index)"] = url
            songIDs.append("s\(index)")
        }

        let session = GaplessPlaybackSession(sampleRate: sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = Double(frames) / rate }

        let backend = GaplessRealTimeBackend()
        #if os(iOS)
        backend.activateAudioSession = {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try audio.setActive(true)
        }
        #endif
        let controller = GaplessPlaybackController(
            session: session, backend: backend,
            preparer: GaplessTrackPreparer(provider: GaplessLocalFileProvider(filesByTrackID: files),
                                           renderSampleRate: sampleRate))
        return Rig(engine: backend.engine, backend: backend, controller: controller,
                   session: session, directory: directory)
    }

    static func teardown(_ rig: Rig) {
        rig.controller.stop()
        try? FileManager.default.removeItem(at: rig.directory)
    }

    /// Drive the controller for `seconds`, ticking at the heartbeat rate.
    static func run(_ rig: Rig, seconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            await rig.controller.tick()
            try? await Task.sleep(for: .milliseconds(4))
        }
    }

    // MARK: - Gate wiring

    /// Proves the gate's environment variable actually reached the test runner.
    ///
    /// `xcodebuild` does not forward a bare environment variable to the runner process — it needs the
    /// `TEST_RUNNER_` prefix. Without this marker a gate could report success while every gated test
    /// silently skipped, which has already happened once in this work (`GAPLESS_SOAK=full` ran the
    /// bounded suite, and the identical runtime was the only clue).
    @Test func gateFlagReachesTheTestRunner() {
        if GaplessBufferGate.isEnabled {
            print("GATEFLAG reached runner")
        }
        // Deliberately not asserted: this test also runs inside standard verification, where the
        // flag is absent and that is correct. The gate script requires the marker; standard
        // verification does not.
        #expect(Bool(true))
    }

    // MARK: - Substrate selection

    /// Production schedules PCM buffers, and the substrate cannot change under a playing track.
    @Test func productionUsesPCMBuffersAndRefusesMidTrackSwitch() async throws {
        let rig = try Self.makeRig(trackCount: 4)
        defer { Self.teardown(rig) }
        #expect(rig.backend.schedulingMode == .pcmBuffer, "production default must be pcmBuffer")

        try await rig.controller.play()
        await Self.run(rig, seconds: 0.6)
        #expect(rig.backend.state == .playing)
        #if DEBUG
        // Swapping substrates under a playing track would cut the output stream.
        #expect(rig.backend.setSchedulingMode(.fileSegment) == false)
        #expect(rig.backend.schedulingMode == .pcmBuffer)
        #endif
        rig.controller.stop()
        await rig.backend.settleTransport()
        #if DEBUG
        #expect(rig.backend.setSchedulingMode(.fileSegment) == true)
        #expect(rig.backend.setSchedulingMode(.pcmBuffer) == true)
        #endif
    }

    // MARK: - Automatic playback through the controller

    /// Repeat All through the full controller, proven by captured audio rather than by state.
    @Test func repeatAllPlaysInOrderThroughTheController() async throws {
        let rig = try Self.makeRig(trackCount: 5, frames: 6_615)
        defer { Self.teardown(rig) }
        rig.session.setRepeatMode(.all)

        let capture = GaplessRealTimeCapture(engine: rig.engine)
        capture.start()
        try await rig.controller.play()
        await Self.run(rig, seconds: 6)
        capture.stop()

        let boundaries = rig.controller.observedBoundaries
        let instances = Set(boundaries.map(\.playInstance))
        let songOrder = boundaries.map(\.songID)
        let expectedCycle = (0..<5).map { "s\($0)" }
        let snap = await rig.backend.domainSnapshotForTesting
        print("""
            CIREPEAT boundaries \(boundaries.count)  distinct instances \(instances.count)  \
            order \(songOrder.prefix(12))  \
            openFiles \(rig.backend.openFileCount)  \
            pool \(snap.poolAvailable)/\(snap.poolCapacity)  \
            starvations \(snap.poolStarvations)  \
            chunks \(snap.chunksScheduled)/\(snap.chunksRecycled)  \
            gap \(String(format: "%.4f", capture.longestSilenceSeconds(sampleRate: Self.sampleRate)))s
            """)

        #expect(boundaries.count >= 8, "only \(boundaries.count) boundaries in 6 s")
        // One play instance per actual play: a Repeat All wrap replays a slot, and each replay is a
        // distinct play, not a duplicate of the first.
        #expect(instances.count == boundaries.count, "play instances were reused across plays")
        // Order follows the queue and wraps.
        for (index, songID) in songOrder.enumerated() {
            #expect(songID == expectedCycle[index % 5],
                    "position \(index) played \(songID), expected \(expectedCycle[index % 5])")
        }
        #expect(snap.staleRecycles == 0)
    }

    /// Repeat One replays the same slot as separate play instances, positionally tracked.
    @Test func repeatOneProducesIndependentPlayInstances() async throws {
        let rig = try Self.makeRig(trackCount: 3, frames: 6_615)
        defer { Self.teardown(rig) }
        rig.session.setRepeatMode(.one)

        try await rig.controller.play()
        await Self.run(rig, seconds: 4)

        let boundaries = rig.controller.observedBoundaries
        let songs = Set(boundaries.map(\.songID))
        let instances = Set(boundaries.map(\.playInstance))
        let snap = await rig.backend.domainSnapshotForTesting
        print("""
            CIREPEATONE boundaries \(boundaries.count)  songs \(songs)  \
            distinct instances \(instances.count)  \
            starvations \(snap.poolStarvations)
            """)
        #expect(boundaries.count >= 3, "only \(boundaries.count) replays")
        #expect(songs == ["s0"], "Repeat One left the current item: \(songs)")
        #expect(instances.count == boundaries.count, "replays shared a play instance")
    }

    // MARK: - Transport through the controller

    /// Next, Previous and seek all go through stop-and-reschedule; every buffer must come back and
    /// the timeline must stay monotonic.
    @Test func transportRebuildsTailWithoutLeakingBuffers() async throws {
        let rig = try Self.makeRig(trackCount: 6, frames: 22_050)
        defer { Self.teardown(rig) }

        try await rig.controller.play()
        await Self.run(rig, seconds: 0.5)

        var lastFrame = rig.backend.renderFrame
        for round in 0..<6 {
            switch round % 3 {
            case 0: try await rig.controller.next()
            case 1: _ = try await rig.controller.previous(elapsedSeconds: 5)
            default: try await rig.controller.seek(toSeconds: 0.1)
            }
            await Self.run(rig, seconds: 0.35)
            let frame = rig.backend.renderFrame
            #expect(frame >= lastFrame, "clock went backwards: \(frame) after \(lastFrame)")
            lastFrame = frame
        }

        let readout = await rig.backend.domainReadoutForTesting
        let snap = readout.snapshot
        print("""
            CITRANSPORT tail \(readout.tailGeneration)  \
            pool \(snap.poolAvailable)+\(snap.poolInFlight)/\(snap.poolCapacity)  \
            chunks \(snap.chunksScheduled)/\(snap.chunksRecycled)  \
            staleRecycles \(snap.staleRecycles)  \
            openFiles \(rig.backend.openFileCount)  \
            liveFiles \(GaplessPCMChunkSource.liveFileCount)  \
            liveConverters \(GaplessPCMConverter.liveCount)
            """)

        #expect(readout.tailGeneration > 1, "no tail replacement happened")
        // Buffers are conserved: available + in-flight is always exactly the pool.
        #expect(snap.poolAvailable + snap.poolInFlight == snap.poolCapacity)

        rig.controller.stop()
        await rig.backend.settleTransport()
        let after = await rig.backend.domainReadoutForTesting
        #expect(after.snapshot.poolAvailable == after.snapshot.poolCapacity,
                "stop left \(after.snapshot.poolInFlight) buffers out")
        #expect(after.snapshot.openFiles == 0)
        #expect(after.segments.isEmpty)
    }

    /// Stop and restart repeatedly: the pool, the files and the converters must all come back every
    /// time, not merely on the last one.
    @Test func repeatedStopRestartLeavesNoResidue() async throws {
        let rig = try Self.makeRig(trackCount: 3, frames: 4_410)
        defer { Self.teardown(rig) }
        let descriptorsBefore = GaplessBufferFixtures.openFileDescriptorCount()

        for cycle in 0..<100 {
            try await rig.controller.play()
            await rig.controller.tick()
            rig.controller.stop()
            await rig.backend.settleTransport()
            let snap = await rig.backend.domainSnapshotForTesting
            #expect(snap.poolAvailable == snap.poolCapacity,
                    "cycle \(cycle) left \(snap.poolInFlight) buffers out")
            #expect(snap.openFiles == 0, "cycle \(cycle) left a file open")
        }
        let descriptorGrowth = GaplessBufferFixtures.openFileDescriptorCount() - descriptorsBefore
        let snap = await rig.backend.domainSnapshotForTesting
        print("""
            CISTOPCYCLE 100 cycles  pool \(snap.poolAvailable)/\(snap.poolCapacity)  \
            fdDelta \(descriptorGrowth)  liveFiles \(GaplessPCMChunkSource.liveFileCount)  \
            liveConverters \(GaplessPCMConverter.liveCount)
            """)
        #expect(descriptorGrowth <= 8, "descriptors grew \(descriptorGrowth) over 100 cycles")
        #expect(GaplessPCMChunkSource.liveFileCount == 0)
    }

    // MARK: - No production open-file cache

    /// Production must not retain open `AVAudioFile` objects per URL.
    ///
    /// The DEBUG file path still has an LRU cache, but it is unreachable in production and is not a
    /// bound: the node retains every file it is handed until it stops, whatever the cache does.
    @Test func productionRetainsNoOpenFilesBeyondThePreparationWindow() async throws {
        let rig = try Self.makeRig(trackCount: 12, frames: 4_410)
        defer { Self.teardown(rig) }
        rig.session.setRepeatMode(.all)

        try await rig.controller.play()
        var peakOpenFiles = 0
        var peakLiveFiles = 0
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            await rig.controller.tick()
            peakOpenFiles = max(peakOpenFiles, rig.backend.openFileCount)
            peakLiveFiles = max(peakLiveFiles, GaplessPCMChunkSource.liveFileCount)
            try? await Task.sleep(for: .milliseconds(4))
        }
        let transitions = rig.controller.observedBoundaries.count
        rig.controller.stop()
        await rig.backend.settleTransport()
        try? await Task.sleep(for: .milliseconds(200))

        print("""
            CINOCACHE transitions \(transitions)  peakOpenFiles \(peakOpenFiles)  \
            peakLiveFiles \(peakLiveFiles)  afterStop \(GaplessPCMChunkSource.liveFileCount)  \
            openFiles \(rig.backend.openFileCount)
            """)

        #expect(transitions >= 8, "only \(transitions) transitions")
        // Bounded by the preparation window, not by how many distinct tracks have been played.
        #expect(peakOpenFiles <= 4, "open files peaked at \(peakOpenFiles) over 12 distinct tracks")
        #expect(peakLiveFiles <= 4, "live AVAudioFile count peaked at \(peakLiveFiles)")
        #expect(GaplessPCMChunkSource.liveFileCount == 0, "files still open after stop")
    }

    // MARK: - Integrated resource run (gated)

    /// 1,000 transitions through the full controller, with conversion in the path.
    @Test(.enabled(if: GaplessBufferGate.isEnabled))
    func integratedThousandTransitionsPlateau() async throws {
        // 48 kHz mono so every transition converts, short so 1,000 fit in a test.
        let rig = try Self.makeRig(trackCount: 40, frames: 4_800, sampleRate: 48_000, channels: 1)
        defer { Self.teardown(rig) }
        rig.session.setRepeatMode(.all)

        try await rig.controller.play()
        // Warm up before the baseline: the audio stack's one-time allocation is not growth.
        await Self.run(rig, seconds: 20)
        let baseline = GaplessBufferFixtures.physFootprint()
        let baselineHeap = GaplessBufferFixtures.liveHeapBytes()
        let baselineDescriptors = GaplessBufferFixtures.openFileDescriptorCount()
        let baselineBoundaries = rig.controller.observedBoundaries.count

        var peakOpenFiles = 0
        var peakConverters = 0
        var samples: [Double] = []
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            await rig.controller.tick()
            peakOpenFiles = max(peakOpenFiles, rig.backend.openFileCount)
            peakConverters = max(peakConverters, GaplessPCMConverter.liveCount)
            if samples.count < 5,
               rig.controller.observedBoundaries.count - baselineBoundaries > (samples.count + 1) * 200 {
                samples.append(Double(GaplessBufferFixtures.physFootprint()) / 1_048_576)
            }
            try? await Task.sleep(for: .milliseconds(4))
        }

        let transitions = rig.controller.observedBoundaries.count - baselineBoundaries
        let growthMB = Double(Int64(GaplessBufferFixtures.physFootprint()) - Int64(baseline)) / 1_048_576
        let heapMB = Double(Int64(GaplessBufferFixtures.liveHeapBytes()) - Int64(baselineHeap)) / 1_048_576
        let descriptorGrowth = GaplessBufferFixtures.openFileDescriptorCount() - baselineDescriptors
        let snap = await rig.backend.domainSnapshotForTesting

        print("""
            CISOAK transitions \(transitions)  growth \(String(format: "%.2f", growthMB)) MB  \
            heapDelta \(String(format: "%.2f", heapMB)) MB  fdDelta \(descriptorGrowth)  \
            windows \(samples.map { String(format: "%.1f", $0) })  \
            peakOpenFiles \(peakOpenFiles)  peakConverters \(peakConverters)  \
            pool \(snap.poolAvailable)/\(snap.poolCapacity)  \
            unreconciled \(snap.unreconciledDeposits)  outstanding \(snap.scheduledDepth)  \
            segments \(snap.scheduledSegments)  starvations \(snap.poolStarvations)  \
            staleRecycles \(snap.staleRecycles)  \
            chunks \(snap.chunksScheduled)/\(snap.chunksRecycled)
            """)

        #expect(transitions >= 900, "only \(transitions) transitions")
        #expect(growthMB < 40, "footprint grew \(growthMB) MB")
        #expect(descriptorGrowth <= 8, "descriptors grew \(descriptorGrowth)")
        #expect(peakOpenFiles <= 4, "open files peaked at \(peakOpenFiles)")
        #expect(snap.staleRecycles == 0)
        #expect(snap.scheduledSegments < 64, "segment records grew to \(snap.scheduledSegments)")
    }
}
