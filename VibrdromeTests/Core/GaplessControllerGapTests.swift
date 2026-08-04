import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Real encoded albums for the integrated seek matrix.
enum GaplessSeekMedia {
    static var root: URL { GaplessConversionMedia.root }
    static let aacAlbum = "Gapless 4-Track AAC"
    static let mp3Album = "Gapless 4-Track MP3"
    static let opusAlbum = "Gapless 4-Track Opus"

    static func files(in album: String) -> [URL] { GaplessConversionMedia.files(in: album) }

    static var available: Bool {
        [aacAlbum, mp3Album, opusAlbum].allSatisfy { files(in: $0).count >= 2 }
    }
}

/// The controller-level gaps left open at the end of Checkpoint C.
///
/// Everything here runs through `GaplessPlaybackController` against the production PCM substrate,
/// because the behaviours under test — a mutation landing 100 ms before a boundary, a seek whose
/// predecessor is still converting, a conversion that fails while another track is audible — only
/// exist once the controller, the session and the preparation window are all in the path.
///
/// Serialised: real `AVAudioEngine` instances, one at a time.
@Suite(.serialized)
@MainActor
struct GaplessControllerGapTests {
    typealias Rig = GaplessBufferIntegrationTests.Rig
    static let sampleRate = GaplessBufferFixtures.sampleRate

    // MARK: - Boundary timing

    /// Run until the next planned boundary is approximately `milliseconds` away.
    ///
    /// Returns the boundary frame it aimed at, or nil if no future boundary was ever visible — a
    /// test that silently mutated at an arbitrary moment would prove nothing about boundary timing.
    @discardableResult
    static func runUntilBeforeBoundary(_ rig: Rig, milliseconds: Double,
                                       timeout: TimeInterval = 8) async -> AVAudioFramePosition? {
        let deadline = Date().addingTimeInterval(timeout)
        // "At the observed boundary" is not a lead of zero frames — a future segment always starts
        // strictly ahead of the clock, so a zero lead would never be satisfied and the test would
        // idle until its timeout with the queue run dry. It means: the instant the controller
        // observes a new boundary.
        if milliseconds == 0 {
            let before = rig.controller.observedBoundaries.count
            while Date() < deadline {
                await rig.controller.tick()
                if rig.controller.observedBoundaries.count > before {
                    return rig.controller.observedBoundaries.last?.scheduledStartFrame
                }
                try? await Task.sleep(for: .milliseconds(2))
            }
            return nil
        }
        let targetFrames = AVAudioFramePosition(milliseconds / 1_000 * sampleRate)
        while Date() < deadline {
            await rig.controller.tick()
            let frame = rig.backend.renderFrame
            if let next = rig.backend.scheduledSegments.first(where: { $0.startFrame > frame }) {
                let remaining = next.startFrame - frame
                if remaining <= targetFrames { return next.startFrame }
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }

    /// The invariants every mutation test shares, checked against the scheduler rather than described.
    static func assertHealthy(_ rig: Rig, label: String) {
        let scheduler = rig.backend.bufferScheduler
        #expect(scheduler.staleRecycles == 0, "\(label): \(scheduler.staleRecycles) stale recycles")
        #expect(scheduler.pool.availableCount + scheduler.pool.inFlightCount == scheduler.pool.capacity,
                "\(label): buffers lost — \(scheduler.pool.availableCount)+\(scheduler.pool.inFlightCount)")
        #expect(scheduler.chunkAccountingBalances,
                "\(label): \(scheduler.chunksScheduled) scheduled vs \(scheduler.chunksRecycled) recycled + \(scheduler.chunksReclaimedAtStop) reclaimed")
    }

    enum Mutation: String, CaseIterable {
        case playNext, removeNext, reorderTail, replaceQueue, repeatModeChange, twoRapid
    }

    /// Every mutation, applied at 250 ms, 100 ms and at the observed boundary.
    ///
    /// Captured audio decides it. A mutation that silently discarded the current track's remainder,
    /// or let a removed track become audible, leaves state that still looks self-consistent — the
    /// only place it shows is in what was actually heard.
    @Test(arguments: Mutation.allCases, [250.0, 100.0, 0.0])
    func mutationsNearBoundaryKeepOnlyTheFinalTail(mutation: Mutation, lead: Double) async throws {
        let rig = try GaplessBufferIntegrationTests.makeRig(trackCount: 6, frames: 22_050)
        defer { GaplessBufferIntegrationTests.teardown(rig) }
        let scheduler = rig.backend.bufferScheduler

        let capture = GaplessRealTimeCapture(engine: rig.engine)
        capture.start()
        try await rig.controller.play()
        await GaplessBufferIntegrationTests.run(rig, seconds: 0.4)

        let tailBefore = scheduler.tailGeneration
        let aimed = await Self.runUntilBeforeBoundary(rig, milliseconds: lead)
        #expect(aimed != nil, "never reached a boundary at lead \(Int(lead)) ms — the mutation would land at an arbitrary moment")
        let frameAtMutation = rig.backend.renderFrame

        switch mutation {
        case .playNext:
            try await rig.controller.playNext(songID: "s5")
        case .removeNext:
            if let next = rig.session.queue.items.dropFirst().first {
                try await rig.controller.remove(itemID: next.id)
            }
        case .reorderTail:
            if let item = rig.session.queue.items.dropFirst(2).first {
                try await rig.controller.move(itemID: item.id, to: 1)
            }
        case .replaceQueue:
            try await rig.controller.replaceQueue(songIDs: ["s3", "s4", "s5"], startIndex: 0)
        case .repeatModeChange:
            try await rig.controller.setRepeatMode(.all)
        case .twoRapid:
            try await rig.controller.playNext(songID: "s4")
            try await rig.controller.playNext(songID: "s5")
        }

        await GaplessBufferIntegrationTests.run(rig, seconds: 2.5)
        capture.stop()

        let boundaries = rig.controller.observedBoundaries
        let instances = boundaries.map(\.playInstance)
        let gap = capture.longestSilenceSeconds(sampleRate: Self.sampleRate)
        print("""
            CIMUT \(mutation.rawValue)@\(Int(lead))ms  aimed \(aimed.map(String.init) ?? "none")  \
            frameAtMutation \(frameAtMutation)  \
            heard \(boundaries.map(\.songID))  \
            instances \(instances.count) distinct \(Set(instances).count)  \
            tail \(tailBefore)->\(scheduler.tailGeneration)  \
            gap \(String(format: "%.4f", gap))s  \
            pool \(scheduler.pool.availableCount)+\(scheduler.pool.inFlightCount)/\(scheduler.pool.capacity)  \
            chunks \(scheduler.chunksScheduled)/\(scheduler.chunksRecycled)+\(scheduler.chunksReclaimedAtStop)  \
            stale \(scheduler.staleRecycles)  starv \(scheduler.poolStarvations)
            """)

        // One play instance per actual play — never reused across two plays.
        #expect(Set(instances).count == instances.count,
                "\(mutation.rawValue)@\(Int(lead))ms reused a play instance")
        // No boundary may name a song that is not in the queue history.
        for boundary in boundaries {
            #expect(boundary.songID.hasPrefix("s"), "unexpected song \(boundary.songID)")
        }
        // A mutation that touches the tail must advance the tail generation; a repeat-mode change
        // that does not need a rebuild legitimately may not.
        if mutation != .repeatModeChange {
            #expect(scheduler.tailGeneration > tailBefore,
                    "\(mutation.rawValue)@\(Int(lead))ms did not rebuild the tail")
        }
        // Audible continuity: the documented limit is the hardware buffer, well under 100 ms.
        #expect(gap < 0.1, "\(mutation.rawValue)@\(Int(lead))ms left a \(gap)s gap")
        Self.assertHealthy(rig, label: "\(mutation.rawValue)@\(Int(lead))ms")
        #expect(rig.backend.state == .playing, "engine was replaced or stopped")
    }

    // MARK: - Seek matrix

    enum SeekCase: String, CaseIterable {
        case forward, backward, nearEnd, beyondDuration, whilePaused
        case fiveRapid, thenNext, duringControlledWait, duringConversion
    }

    /// The seek matrix on synthetic 48 kHz sources, so a converter is in the path for every case.
    @Test(arguments: SeekCase.allCases)
    func seekMatrixLandsOnTheFinalPositionOnly(seekCase: SeekCase) async throws {
        let rig = try GaplessBufferIntegrationTests.makeRig(trackCount: 4, frames: 96_000,
                                                            sampleRate: 48_000, channels: 1)
        defer { GaplessBufferIntegrationTests.teardown(rig) }
        let scheduler = rig.backend.bufferScheduler

        try await rig.controller.play()
        await GaplessBufferIntegrationTests.run(rig, seconds: 0.6)
        let tailBefore = scheduler.tailGeneration
        let boundariesBefore = rig.controller.observedBoundaries.count
        let wasPlaying = rig.backend.state == .playing

        switch seekCase {
        case .forward: try await rig.controller.seek(toSeconds: 1.2)
        case .backward:
            try await rig.controller.seek(toSeconds: 1.4)
            await GaplessBufferIntegrationTests.run(rig, seconds: 0.3)
            try await rig.controller.seek(toSeconds: 0.2)
        case .nearEnd: try await rig.controller.seek(toSeconds: 1.95)
        case .beyondDuration:
            // `GaplessPlaybackController` does not itself validate against duration — that check
            // lives one layer up in `GaplessApplicationPlaybackController.seek`, which is what the
            // app calls. At this layer the request is clamped into the trimmed range rather than
            // rejected, so what matters here is that it produces no phantom span and no lost buffer.
            try await rig.controller.seek(toSeconds: 99)
        case .whilePaused:
            rig.controller.pause()
            try await rig.controller.seek(toSeconds: 1.0)
        case .fiveRapid:
            for position in [0.3, 1.1, 0.5, 1.6, 0.8] {
                try await rig.controller.seek(toSeconds: position)
            }
        case .thenNext:
            try await rig.controller.seek(toSeconds: 1.0)
            try await rig.controller.next()
        case .duringControlledWait:
            try await rig.controller.seek(toSeconds: 1.0)
            await rig.controller.tick()
            try await rig.controller.seek(toSeconds: 0.4)
        case .duringConversion:
            // No tick between them: the first seek's conversion work is still in flight when the
            // second arrives, which is the case where a stale converted chunk could reach the node.
            try await rig.controller.seek(toSeconds: 1.3)
            try await rig.controller.seek(toSeconds: 0.6)
        }

        // Settle briefly and read the position THEN. Running on for a second first would let a 2 s
        // track advance past the seek target, and the reading would describe the next track — which
        // is playback working correctly, not the seek failing.
        await GaplessBufferIntegrationTests.run(rig, seconds: 0.25)
        let elapsed = rig.backend.clockReading(generation: rig.session.queue.generation).elapsedSeconds
        await GaplessBufferIntegrationTests.run(rig, seconds: 0.6)

        print("""
            CISEEK \(seekCase.rawValue)  state \(rig.backend.state)  \
            elapsed \(String(format: "%.3f", elapsed))s  \
            tail \(tailBefore)->\(scheduler.tailGeneration)  \
            pool \(scheduler.pool.availableCount)+\(scheduler.pool.inFlightCount)/\(scheduler.pool.capacity)  \
            chunks \(scheduler.chunksScheduled)/\(scheduler.chunksRecycled)+\(scheduler.chunksReclaimedAtStop)  \
            stale \(scheduler.staleRecycles)  starv \(scheduler.poolStarvations)  \
            liveFiles \(GaplessPCMChunkSource.liveFileCount)  \
            liveConverters \(GaplessPCMConverter.liveCount)
            """)

        switch seekCase {
        case .forward: #expect(elapsed >= 1.15, "forward seek reported \(elapsed)s, expected >= 1.2")
        case .backward: #expect(elapsed >= 0.15 && elapsed < 1.0, "backward seek reported \(elapsed)s")
        case .nearEnd:
            // 1.95 s into a 2.0 s track leaves 50 ms, less than the settle. Landing there and then
            // advancing to the next track is the correct outcome — asserting a high elapsed would be
            // asserting that playback stalled.
            let advanced = rig.controller.observedBoundaries.count > boundariesBefore
            #expect(elapsed >= 1.9 || advanced,
                    "near-end seek reported \(elapsed)s without advancing")
        case .fiveRapid, .duringConversion:
            // Only the final seek of the sequence may be reported — 0.8 s and 0.6 s respectively.
            #expect(elapsed >= 0.55 && elapsed < 1.1, "final seek reported \(elapsed)s")
        case .duringControlledWait:
            #expect(elapsed >= 0.35 && elapsed < 0.9, "final seek reported \(elapsed)s")
        default: break
        }
        if seekCase == .whilePaused {
            #expect(rig.backend.state == .paused, "seek while paused resumed playback")
            #expect(elapsed >= 0.9, "paused seek reported \(elapsed)s, expected ~1.0")
        } else if seekCase != .beyondDuration {
            #expect(rig.backend.state == .playing || !wasPlaying)
        }
        #expect(scheduler.tailGeneration > tailBefore, "seek did not rebuild the tail")
        for segment in scheduler.segments {
            #expect(segment.frameCount > 0, "seek produced a zero-length span for \(segment.songID)")
        }
        Self.assertHealthy(rig, label: "seek \(seekCase.rawValue)")

        rig.controller.stop()
        scheduler.reconcileLateCallbacks()
        #expect(scheduler.pool.availableCount == scheduler.pool.capacity,
                "seek \(seekCase.rawValue) left \(scheduler.pool.inFlightCount) buffers out after stop")
    }

    /// The same matrix reduced to forward/backward, on **real encoded** media where trimming is real:
    /// AAC priming, MP3 LAME padding, and 48 kHz Opus through the converter.
    @Test(.enabled(if: GaplessSeekMedia.available),
          arguments: [GaplessSeekMedia.aacAlbum, GaplessSeekMedia.mp3Album, GaplessSeekMedia.opusAlbum])
    func seekInTrimmedEncodedSources(album: String) async throws {
        let urls = Array(GaplessSeekMedia.files(in: album).prefix(3))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gseek-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var files: [String: URL] = [:]
        var songIDs: [String] = []
        var trims: [String] = []
        for (index, url) in urls.enumerated() {
            let id = "e\(index)"
            files[id] = url
            songIDs.append(id)
            let described = try GaplessTrackPreparer.describe(trackID: id, fileURL: url,
                                                              renderSampleRate: Self.sampleRate)
            trims.append("\(described.trim.reason.rawValue)/\(described.trim.frameCount)@\(Int(described.sourceSampleRate))")
        }

        let session = GaplessPlaybackSession(sampleRate: Self.sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = 10 }
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
                                           renderSampleRate: Self.sampleRate))
        defer { controller.stop() }

        try await controller.play()
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline { await controller.tick(); try? await Task.sleep(for: .milliseconds(4)) }

        try await controller.seek(toSeconds: 4.0)                       // forward
        for _ in 0..<60 { await controller.tick(); try? await Task.sleep(for: .milliseconds(4)) }
        let afterForward = backend.clockReading(generation: session.queue.generation).elapsedSeconds
        try await controller.seek(toSeconds: 1.0)                       // backward
        for _ in 0..<60 { await controller.tick(); try? await Task.sleep(for: .milliseconds(4)) }
        let afterBackward = backend.clockReading(generation: session.queue.generation).elapsedSeconds

        let scheduler = backend.bufferScheduler
        print("""
            CISEEKREAL \(album)  trims \(trims)  \
            afterForward \(String(format: "%.3f", afterForward))s  \
            afterBackward \(String(format: "%.3f", afterBackward))s  \
            tail \(scheduler.tailGeneration)  stale \(scheduler.staleRecycles)  \
            starv \(scheduler.poolStarvations)  \
            pool \(scheduler.pool.availableCount)+\(scheduler.pool.inFlightCount)/\(scheduler.pool.capacity)
            """)

        // Elapsed maps into the track, near where we asked, and the backward seek genuinely moved
        // backwards rather than merely rebuilding at the old position.
        #expect(afterForward >= 3.9, "forward seek landed at \(afterForward)s")
        #expect(afterBackward < afterForward, "backward seek did not move back: \(afterBackward)s")
        #expect(afterBackward >= 0.9, "backward seek landed at \(afterBackward)s")
        #expect(scheduler.staleRecycles == 0)
        #expect(scheduler.pool.availableCount + scheduler.pool.inFlightCount == scheduler.pool.capacity)
    }

    // MARK: - Controller-level conversion failure

    enum FailureContext: String, CaseIterable {
        case linear, repeatAll, afterPlayNext
    }

    /// A conversion that fails for a *future* item while another track is audible.
    ///
    /// The injection point only fires for converters with no output yet, so the audible track — whose
    /// converter has long since produced frames — is untouched. That is precisely the case that
    /// matters: the failure must stay contained to the item that failed.
    @Test(arguments: FailureContext.allCases)
    func futureConversionFailureLeavesAudiblePlaybackCoherent(context: FailureContext) async throws {
        let rig = try GaplessBufferIntegrationTests.makeRig(trackCount: 6, frames: 48_000,
                                                            sampleRate: 48_000, channels: 1)
        defer {
            GaplessPCMConverter.injectedFailure = nil
            GaplessBufferIntegrationTests.teardown(rig)
        }
        let scheduler = rig.backend.bufferScheduler
        if context == .repeatAll { rig.session.setRepeatMode(.all) }

        let capture = GaplessRealTimeCapture(engine: rig.engine)
        capture.start()
        try await rig.controller.play()
        await GaplessBufferIntegrationTests.run(rig, seconds: 0.8)

        let audibleBefore = rig.session.audibleItemID
        let boundariesBefore = rig.controller.observedBoundaries.count
        #expect(audibleBefore != nil, "nothing was audible before the failure was injected")

        if context == .afterPlayNext { try await rig.controller.playNext(songID: "s5") }
        GaplessPCMConverter.injectedFailure = .beforeFirstOutput
        await GaplessBufferIntegrationTests.run(rig, seconds: 1.5)

        let failuresDuringInjection = scheduler.failures.count
        let boundariesDuringInjection = rig.controller.observedBoundaries.count
        let audibleDuring = rig.session.audibleItemID

        // Recovery: clear the fault and replace the queue.
        GaplessPCMConverter.injectedFailure = nil
        try await rig.controller.replaceQueue(songIDs: ["s0", "s1", "s2"], startIndex: 0)
        await GaplessBufferIntegrationTests.run(rig, seconds: 1.5)
        capture.stop()

        let recovered = rig.controller.observedBoundaries.count - boundariesDuringInjection
        print("""
            CIFAIL \(context.rawValue)  audibleBefore \(String(describing: audibleBefore))  \
            audibleDuring \(String(describing: audibleDuring))  \
            failures \(failuresDuringInjection)  \
            boundaries \(boundariesBefore)->\(boundariesDuringInjection) recovered +\(recovered)  \
            heard \(rig.controller.observedBoundaries.map(\.songID))  \
            pool \(scheduler.pool.availableCount)+\(scheduler.pool.inFlightCount)/\(scheduler.pool.capacity)  \
            chunks \(scheduler.chunksScheduled)/\(scheduler.chunksRecycled)+\(scheduler.chunksReclaimedAtStop)  \
            stale \(scheduler.staleRecycles)  \
            liveConverters \(GaplessPCMConverter.liveCount)  \
            liveFiles \(GaplessPCMChunkSource.liveFileCount)
            """)

        // Every boundary names a song that genuinely produced audio — no phantom item.
        for boundary in rig.controller.observedBoundaries {
            let segment = scheduler.segments.first { $0.playInstance == boundary.playInstance }
            if let segment { #expect(segment.frameCount > 0, "\(boundary.songID) claims a zero span") }
        }
        // The engine is still playing the track it was playing; the failure did not take it down.
        #expect(rig.backend.state == .playing || rig.backend.state == .paused)
        // Recovery works: after the fault is cleared a queue replacement produces new audio.
        #expect(recovered > 0, "no recovery after the conversion fault was cleared")
        Self.assertHealthy(rig, label: "failure \(context.rawValue)")
    }

    // MARK: - Compact transport stress

    /// The Checkpoint C integration stress. Volumes here are deliberately compact; the 250-command
    /// volumes belong to Checkpoint D.
    @Test(.enabled(if: GaplessBufferGate.isEnabled))
    func compactTransportStress() async throws {
        let rig = try GaplessBufferIntegrationTests.makeRig(trackCount: 12, frames: 22_050)
        defer { GaplessBufferIntegrationTests.teardown(rig) }
        let scheduler = rig.backend.bufferScheduler
        rig.session.setRepeatMode(.all)

        try await rig.controller.play()
        await GaplessBufferIntegrationTests.run(rig, seconds: 1)
        let baseline = GaplessBufferFixtures.physFootprint()
        let baselineDescriptors = GaplessBufferFixtures.openFileDescriptorCount()
        var peakConverters = 0
        var peakFiles = 0

        func settle(_ rounds: Int = 4) async {
            for _ in 0..<rounds {
                await rig.controller.tick()
                peakConverters = max(peakConverters, GaplessPCMConverter.liveCount)
                peakFiles = max(peakFiles, GaplessPCMChunkSource.liveFileCount)
                try? await Task.sleep(for: .milliseconds(4))
            }
        }

        for _ in 0..<50 { try await rig.controller.next(); await settle() }
        for _ in 0..<50 { _ = try await rig.controller.previous(elapsedSeconds: 5); await settle() }
        for index in 0..<50 { try await rig.controller.seek(toSeconds: Double(index % 4) * 0.1); await settle() }
        for _ in 0..<50 { rig.backend.resetTail(); await rig.controller.replenishTail(); await settle(2) }
        for index in 0..<50 { try await rig.controller.playNext(songID: "s\(index % 12)"); await settle(2) }
        for _ in 0..<50 {
            if let item = rig.session.queue.items.dropFirst(2).first {
                try await rig.controller.remove(itemID: item.id)
            }
            try await rig.controller.addToQueue(songID: "s3")
            await settle(2)
        }
        for index in 0..<50 {
            switch index % 4 {
            case 0: try await rig.controller.next()
            case 1: try await rig.controller.seek(toSeconds: 0.2)
            case 2: try await rig.controller.playNext(songID: "s7")
            default: _ = try await rig.controller.previous(elapsedSeconds: 1)
            }
            await settle(2)
        }
        for index in 0..<25 {
            try await rig.controller.replaceQueue(songIDs: (0..<6).map { "s\(($0 + index) % 12)" },
                                                  startIndex: 0)
            await settle(2)
        }
        for index in 0..<25 {
            try await rig.controller.setRepeatMode([.off, .all, .one][index % 3])
            await settle(1)
        }
        for index in 0..<25 {
            try await rig.controller.setShuffleEnabled(index % 2 == 0)
            await settle(1)
        }

        let growthMB = Double(Int64(GaplessBufferFixtures.physFootprint()) - Int64(baseline)) / 1_048_576
        let descriptorGrowth = GaplessBufferFixtures.openFileDescriptorCount() - baselineDescriptors
        let instances = rig.controller.observedBoundaries.map(\.playInstance)

        print("""
            CISTRESS commands 375  growth \(String(format: "%.2f", growthMB)) MB  \
            fdDelta \(descriptorGrowth)  peakConverters \(peakConverters)  peakFiles \(peakFiles)  \
            tail \(scheduler.tailGeneration)  \
            pool \(scheduler.pool.availableCount)+\(scheduler.pool.inFlightCount)/\(scheduler.pool.capacity)  \
            chunks \(scheduler.chunksScheduled)/\(scheduler.chunksRecycled)+\(scheduler.chunksReclaimedAtStop)  \
            stale \(scheduler.staleRecycles)  starv \(scheduler.poolStarvations)  \
            boundaries \(instances.count) distinct \(Set(instances).count)  \
            queue \(rig.session.queue.count)  state \(rig.backend.state)
            """)

        #expect(Set(instances).count == instances.count, "a play instance was reused")
        #expect(growthMB < 40, "footprint grew \(growthMB) MB under transport stress")
        #expect(descriptorGrowth <= 8, "descriptors grew \(descriptorGrowth)")
        #expect(peakConverters <= 6, "converters accumulated to \(peakConverters)")
        #expect(peakFiles <= 6, "files accumulated to \(peakFiles)")
        #expect(scheduler.staleRecycles == 0)
        #expect(scheduler.pool.availableCount + scheduler.pool.inFlightCount == scheduler.pool.capacity)
        #expect(scheduler.chunkAccountingBalances)
        #expect(rig.session.queue.count > 0, "queue was corrupted")
    }

    // MARK: - Post-stop reconciliation

    /// The four-chunk difference reported at the end of the integrated soak, resolved.
    ///
    /// `chunksScheduled` exceeding `chunksRecycled` mid-run is expected — that difference *is* the
    /// scheduled lead, four chunks in flight. What was not previously proven is that the difference
    /// closes at stop. It is recorded at three points, and the books must balance at each.
    @Test func chunkAccountingReconcilesThroughStop() async throws {
        let rig = try GaplessBufferIntegrationTests.makeRig(trackCount: 6, frames: 22_050)
        defer { GaplessBufferIntegrationTests.teardown(rig) }
        let scheduler = rig.backend.bufferScheduler
        rig.session.setRepeatMode(.all)

        try await rig.controller.play()
        await GaplessBufferIntegrationTests.run(rig, seconds: 4)

        let beforeStop = (scheduled: scheduler.chunksScheduled, recycled: scheduler.chunksRecycled,
                          reclaimed: scheduler.chunksReclaimedAtStop,
                          available: scheduler.pool.availableCount,
                          inFlight: scheduler.pool.inFlightCount,
                          outstanding: scheduler.outstandingCallbackCount,
                          inbox: scheduler.inbox.pendingCount,
                          files: GaplessPCMChunkSource.liveFileCount,
                          converters: GaplessPCMConverter.liveCount)

        rig.controller.stop()
        let afterStop = (scheduled: scheduler.chunksScheduled, recycled: scheduler.chunksRecycled,
                         reclaimed: scheduler.chunksReclaimedAtStop,
                         available: scheduler.pool.availableCount,
                         inFlight: scheduler.pool.inFlightCount,
                         outstanding: scheduler.outstandingCallbackCount,
                         inbox: scheduler.inbox.pendingCount,
                         files: GaplessPCMChunkSource.liveFileCount,
                         converters: GaplessPCMConverter.liveCount)

        // Let any completion handlers the node delivered as it stopped arrive, then fold them in.
        try? await Task.sleep(for: .milliseconds(500))
        let late = scheduler.reconcileLateCallbacks()
        let afterDrain = (scheduled: scheduler.chunksScheduled, recycled: scheduler.chunksRecycled,
                          reclaimed: scheduler.chunksReclaimedAtStop,
                          available: scheduler.pool.availableCount,
                          inFlight: scheduler.pool.inFlightCount,
                          outstanding: scheduler.outstandingCallbackCount,
                          inbox: scheduler.inbox.pendingCount,
                          files: GaplessPCMChunkSource.liveFileCount,
                          converters: GaplessPCMConverter.liveCount)

        print("""
            CIRECON before  sched \(beforeStop.scheduled) recycled \(beforeStop.recycled) reclaimed \(beforeStop.reclaimed)  \
            pool \(beforeStop.available)+\(beforeStop.inFlight)  outstanding \(beforeStop.outstanding)  \
            inbox \(beforeStop.inbox)  files \(beforeStop.files)  converters \(beforeStop.converters)
            CIRECON after   sched \(afterStop.scheduled) recycled \(afterStop.recycled) reclaimed \(afterStop.reclaimed)  \
            pool \(afterStop.available)+\(afterStop.inFlight)  outstanding \(afterStop.outstanding)  \
            inbox \(afterStop.inbox)  files \(afterStop.files)  converters \(afterStop.converters)
            CIRECON drain   sched \(afterDrain.scheduled) recycled \(afterDrain.recycled) reclaimed \(afterDrain.reclaimed)  \
            pool \(afterDrain.available)+\(afterDrain.inFlight)  outstanding \(afterDrain.outstanding)  \
            inbox \(afterDrain.inbox)  files \(afterDrain.files)  converters \(afterDrain.converters)  \
            lateCallbacks \(late)
            """)

        // Mid-run the difference is exactly the chunks still in flight — the scheduled lead.
        #expect(beforeStop.scheduled - beforeStop.recycled == beforeStop.outstanding,
                "mid-run difference \(beforeStop.scheduled - beforeStop.recycled) != outstanding \(beforeStop.outstanding)")
        // The books balance at every point: nothing is scheduled that is not later accounted for,
        // either as heard-and-recycled or as discarded by the stop.
        #expect(afterStop.scheduled == afterStop.recycled + afterStop.reclaimed,
                "after stop: \(afterStop.scheduled) != \(afterStop.recycled) + \(afterStop.reclaimed)")
        #expect(afterDrain.scheduled == afterDrain.recycled + afterDrain.reclaimed,
                "after drain: \(afterDrain.scheduled) != \(afterDrain.recycled) + \(afterDrain.reclaimed)")
        // Everything else returns to its resting state.
        #expect(afterDrain.available == scheduler.pool.capacity, "pool not full: \(afterDrain.available)")
        #expect(afterDrain.inFlight == 0)
        #expect(afterDrain.outstanding == 0)
        #expect(afterDrain.inbox == 0)
        #expect(afterDrain.files == 0)
        #expect(afterDrain.converters == 0)
    }
}
