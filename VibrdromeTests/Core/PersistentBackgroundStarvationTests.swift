import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Does PCM continuity survive when the main actor stops running? **It must, now.**
///
/// **Why this is the right experiment.** iOS keeps a `UIBackgroundModes: audio` app alive while it
/// plays, but it does not promise that ordinary main-actor work keeps its foreground cadence —
/// timers coalesce and main-thread work is deprioritised. The refill path used to be `@MainActor`
/// end to end, and a measured 1 s main-actor stall starved it: four render-side recycle deposits
/// where continuous playback needed eleven — the click-and-pause heard on device in the background.
/// Production now routes every PCM operation and every player-node mutation through
/// `GaplessAudioDomain` on `GaplessAudioActor`, so this suite is the **acceptance criterion**: with
/// the main actor blocked for up to five seconds, the production backend must keep supplying PCM.
///
/// Blocking the main actor synchronously reproduces exactly the background condition: the heartbeat
/// and every main-actor task are unable to run, while the audio render thread keeps pulling.
///
/// **Evidence rule.** Supply is judged on render-side recycle deposits and on replacement chunks
/// actually produced — never on `renderFrame`, which is proven to advance through silence (it
/// reported a zero deficit for a window the deposit count proved starved), and never on main-actor
/// bookkeeping such as in-flight counts, which simply freeze when the main actor cannot run. The
/// inbox is written by the render thread under its own lock; it is the one signal a stalled main
/// actor cannot distort.
@Suite(.serialized)
@MainActor
struct PersistentBackgroundStarvationTests {

    private static let sampleRate = GaplessBufferFixtures.sampleRate
    private static let chunkFrames = 4_096.0

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("starve-\(UInt64.random(in: 0..<UInt64.max))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func makeAssembly(files: [String: URL], directory: URL) -> PersistentPlaybackAssembly {
        PersistentPlaybackAssembly(
            session: GaplessPlaybackSession(sampleRate: Self.sampleRate),
            backend: GaplessRealTimeBackend(),
            preparer: GaplessTrackPreparer(
                provider: GaplessLocalFileProvider(filesByTrackID: files),
                renderSampleRate: Self.sampleRate),
            cacheDirectory: directory)
    }

    private func makeFiles(_ ids: [String], frames: Int, in directory: URL) throws -> [String: URL] {
        var files: [String: URL] = [:]
        for (index, id) in ids.enumerated() {
            let url = directory.appendingPathComponent("\(id).wav")
            try GaplessBufferFixtures.writeStereoWav(
                url: url, frequency: 330 + Double(index) * 110,
                frames: frames, sampleRate: Self.sampleRate)
            files[id] = url
        }
        return files
    }

    /// Drive real ticks until the render clock is genuinely moving.
    private func driveUntilRendering(_ controller: GaplessPlaybackController) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            await controller.tick()
            if controller.backend.renderFrame > 0 { return }
            try? await Task.sleep(for: .milliseconds(4))
        }
    }

    /// Drive real ticks until the clock reaches `frame` (or the deadline passes).
    private func drive(_ controller: GaplessPlaybackController, untilFrame frame: AVAudioFramePosition,
                       deadlineSeconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(deadlineSeconds)
        while Date() < deadline, controller.backend.renderFrame < frame {
            await controller.tick()
            try? await Task.sleep(for: .milliseconds(4))
        }
    }

    /// Hold the main actor for `milliseconds`, exactly as a background throttle would.
    ///
    /// Synchronous on purpose: an `await` would yield and let the very tasks under test run, which
    /// would measure nothing.
    private func blockMainActor(milliseconds: Int) {
        let deadline = Date().addingTimeInterval(Double(milliseconds) / 1000)
        while Date() < deadline { /* deliberately spinning: the main actor must be unavailable */ }
    }

    /// One measurement: what the audio domain supplied while the main actor was unavailable.
    private struct Starvation {
        /// Local copy so the value type is usable without main-actor isolation.
        static let sampleRate = GaplessBufferFixtures.sampleRate
        let blockMilliseconds: Int
        let renderedFrames: AVAudioFramePosition
        let expectedFrames: AVAudioFramePosition
        /// Buffers the RENDER THREAD reported finishing during the block. Deposited under a lock
        /// from the completion callback — not main-actor bookkeeping that freezes with the stall.
        let renderDeposits: Int
        /// Replacement chunks the domain produced and scheduled during the block.
        let chunksProduced: Int
        let scheduledDepthAfter: Int
        let poolBalanced: Bool
        let accountingBalances: Bool
        let poolStarvations: Int
        /// Chunks a continuously-rendering node consumes in that much wall time.
        var chunksNeeded: Int { Int((Double(expectedFrames) / 4_096).rounded()) }
        /// Supplied means the node kept being fed: it reported finishing roughly what continuous
        /// playback needed, and replacements were produced to match. Without refill it can only
        /// ever report the ~4 chunks it already held.
        var supplied: Bool {
            renderDeposits >= chunksNeeded - 1 && chunksProduced >= chunksNeeded - 1
        }
        var deficitFrames: AVAudioFramePosition { max(0, expectedFrames - renderedFrames) }
        var deficitSeconds: Double { Double(deficitFrames) / Self.sampleRate }
        var described: String {
            String(format: "stall %5d ms -> deposits %3d, produced %3d, needed %3d, depth %d",
                   blockMilliseconds, renderDeposits, chunksProduced, chunksNeeded,
                   scheduledDepthAfter)
                + String(format: " | clock deficit %.3f s -> %@", deficitSeconds,
                         supplied ? "SUPPLIED" : "STARVED")
        }
    }

    private func measure(_ assembly: PersistentPlaybackAssembly,
                         blockMilliseconds: Int) async -> Starvation {
        let backend = assembly.backend
        let before = await backend.domainSnapshotForTesting
        let framesBefore = backend.renderFrame
        let startedAt = Date()

        blockMainActor(milliseconds: blockMilliseconds)

        let elapsed = Date().timeIntervalSince(startedAt)
        let framesAfter = backend.renderFrame
        let after = await backend.domainSnapshotForTesting
        return Starvation(
            blockMilliseconds: blockMilliseconds,
            renderedFrames: framesAfter - framesBefore,
            expectedFrames: AVAudioFramePosition(elapsed * Self.sampleRate),
            renderDeposits: after.renderDeposits - before.renderDeposits,
            chunksProduced: after.chunksScheduled - before.chunksScheduled,
            scheduledDepthAfter: after.scheduledDepth,
            poolBalanced: after.poolAvailable + after.poolInFlight == after.poolCapacity,
            accountingBalances: after.accountingBalances,
            poolStarvations: after.poolStarvations - before.poolStarvations)
    }

    // MARK: - The structural claim, stated as code

    /// The production refill path runs on the audio domain, not the main actor.
    ///
    /// Structural half: every method of `GaplessAudioDomain` is isolated to `GaplessAudioActor`, so
    /// the compiler already proves refill cannot require main-actor time. This pins the observable
    /// half — production really does construct one domain over its graph, exactly one, with the
    /// pool geometry the stall thresholds below assume.
    @Test func theRefillPathRunsOnTheAudioDomain() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["m0"], frames: 441_000, in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            #expect(assembly.backend.audioDomain == nil,
                    "the domain must be lazy: nothing played, nothing allocated")
            assembly.session.replaceQueue(songIDs: ["m0"])
            try await assembly.controller.play()

            #expect(assembly.backend.audioDomain != nil,
                    "production did not construct its audio domain")
            let snapshot = await assembly.backend.domainSnapshotForTesting
            #expect(snapshot.poolCapacity == 6,
                    "pool capacity changed; the lead calculation below assumes 6")
            let leadSeconds = 4 * Self.chunkFrames / Self.sampleRate
            #expect(abs(leadSeconds - 0.372) < 0.01,
                    "scheduled lead is \(leadSeconds) s — the starvation thresholds assume ~0.372 s")
        }
    }

    // MARK: - The acceptance table (production path, single track)

    /// PCM keeps being supplied by the **production backend** while the main actor is blocked, for
    /// every window up to five seconds. This was the whole point of the cutover: the same table
    /// measured before it showed STARVED from 500 ms up.
    ///
    /// The render clock is still NOT the detector — it advances through silence, and historically
    /// reported a zero deficit for a window the deposit count proved starved. Supply is judged on
    /// deposits and produced chunks; the clock deficit is printed as context only.
    @Test func mainActorStallCharacterisation() async throws {
        try await withTemporaryDirectory { directory in
            // 30 s of audio: the stalls plus recovery must never run into the end of the track.
            let files = try makeFiles(["s0"], frames: 1_323_000, in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            assembly.session.replaceQueue(songIDs: ["s0"])
            try await assembly.controller.play()
            await driveUntilRendering(assembly.controller)
            #expect(assembly.backend.renderFrame > 0, "the fixture never started rendering")

            var results: [Starvation] = []
            for window in [100, 250, 500, 1_000, 2_000, 5_000] {
                results.append(await measure(assembly, blockMilliseconds: window))
                // Let the engine recover fully between measurements.
                for _ in 0..<40 {
                    await assembly.controller.tick()
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }

            for result in results { print("STARVATION \(result.described)") }

            for result in results {
                #expect(result.supplied,
                        "production starved with the main actor blocked: \(result.described)")
                #expect(result.poolBalanced,
                        "pool accounting broke during a \(result.blockMilliseconds) ms stall")
                #expect(result.accountingBalances,
                        "chunk ledger broke during a \(result.blockMilliseconds) ms stall")
                #expect(result.poolStarvations == 0,
                        "the pool starved during a \(result.blockMilliseconds) ms stall")
            }
            // After recovery every render deposit must be reconciled — a token the domain never
            // drained would be a buffer the pool believes is still out.
            let settled = await assembly.backend.domainSnapshotForTesting
            #expect(settled.unreconciledDeposits == 0,
                    "\(settled.unreconciledDeposits) recycle tokens were never reconciled")
            #expect(results.count == 6)
        }
    }

    /// A stall shorter than the scheduled lead must not starve audio — the floor the architecture
    /// claimed even before the cutover, preserved as its own regression.
    @Test func audioSurvivesAMainActorStallShorterThanTheScheduledLead() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["p0"], frames: 441_000, in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            assembly.session.replaceQueue(songIDs: ["p0"])
            try await assembly.controller.play()
            await driveUntilRendering(assembly.controller)

            let result = await measure(assembly, blockMilliseconds: 100)
            #expect(result.supplied,
                    "a 100 ms main-actor stall starved audio: \(result.described)")
            #expect(result.deficitSeconds < 0.025,
                    "the clock fell behind inside the scheduled lead: \(result.described)")
        }
    }

    // MARK: - Prepared boundaries under stall (Outcome A)

    /// Cross a real automatic track boundary while the main actor is unavailable, for stalls of
    /// 500 ms, 1 s, 2 s and 5 s — each positioned to begin just before a boundary.
    ///
    /// This is the proven Outcome A fixture: the rolling window has already materialized, opened
    /// and enqueued the upcoming tracks before the stall begins, so only PCM refill — the part the
    /// domain owns — is exercised by the block. Preparation itself (`replenishTail`,
    /// `GaplessTrackPreparer`) stays on the main actor by design and is given time to run between
    /// stalls.
    @Test func preparedBoundariesSurviveMainActorStalls() async throws {
        try await withTemporaryDirectory { directory in
            let trackFrames = 352_800   // 8 s per track: a 5 s stall spans exactly one boundary
            let ids = ["b0", "b1", "b2", "b3", "b4"]
            let files = try makeFiles(ids, frames: trackFrames, in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            assembly.session.replaceQueue(songIDs: ids)
            for id in ids {
                assembly.session.songDurations[id] = Double(trackFrames) / Self.sampleRate
            }
            try await assembly.controller.play()
            await driveUntilRendering(assembly.controller)

            // Outcome A precondition: the window is filled before any stall — the successor is
            // already enqueued and materialized, not merely requested.
            for _ in 0..<60 {
                await assembly.controller.tick()
                try? await Task.sleep(for: .milliseconds(5))
            }
            let readyBefore = await assembly.backend.domainSnapshotForTesting
            #expect(readyBefore.liveSources >= 2,
                    "the window never enqueued the successor; this would measure Outcome B")

            let lead = AVAudioFramePosition(0.5 * Self.sampleRate)
            for (index, window) in [500, 1_000, 2_000, 5_000].enumerated() {
                let boundary = AVAudioFramePosition((index + 1) * trackFrames)
                await drive(assembly.controller, untilFrame: boundary - lead, deadlineSeconds: 12)
                #expect(assembly.backend.renderFrame < boundary,
                        "boundary \(index) had already passed; the stall would measure nothing")

                let result = await measure(assembly, blockMilliseconds: window)
                print("BOUNDARY \(result.described)")
                #expect(result.supplied,
                        "the boundary at \(boundary) starved under a \(window) ms stall: \(result.described)")
                #expect(result.poolBalanced && result.accountingBalances,
                        "recycle accounting broke crossing boundary \(index): \(result.described)")

                // Recovery: the main actor is back; boundary observation and the queue catch up.
                for _ in 0..<40 {
                    await assembly.controller.tick()
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }

            let heard = assembly.controller.observedBoundaries.map(\.songID)
            print("BOUNDARY occurrences heard: \(heard)")
            // Every occurrence exactly once, in order — no duplicate, no skip, no hole.
            let instances = assembly.controller.observedBoundaries.map(\.playInstance)
            #expect(Set(instances).count == instances.count, "an occurrence reported a boundary twice")
            #expect(instances.map(\.rawValue) == instances.map(\.rawValue).sorted(),
                    "play instances became audible out of order")
            #expect(heard == ids, "occurrences heard were \(heard), expected \(ids)")
            // The queue caught up after the main actor resumed.
            #expect(assembly.session.queue.currentIndex == ids.count - 1,
                    "queue index never caught up: \(assembly.session.queue.currentIndex)")
            let settled = await assembly.backend.domainSnapshotForTesting
            #expect(settled.unreconciledDeposits == 0, "recycle tokens left unreconciled")
            #expect(settled.accountingBalances, "chunk ledger does not reconcile after the run")
        }
    }

    // MARK: - Adversarial lifecycle

    /// Stop while refill is live: teardown completes, resources recover fully, and neither a late
    /// recycle wakeup nor a late tick can schedule anything afterwards.
    @Test func stopWithRefillInFlightRecoversEverythingAndStaysStopped() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["r0"], frames: 441_000, in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            assembly.session.replaceQueue(songIDs: ["r0"])
            try await assembly.controller.play()
            await driveUntilRendering(assembly.controller)
            // Real deposits are flowing — a stop here races live recycle wakeups by construction.
            try? await Task.sleep(for: .milliseconds(400))
            let running = await assembly.backend.domainSnapshotForTesting
            #expect(running.renderDeposits > 0, "the fixture never recycled; the race is not real")

            assembly.controller.stop()
            await assembly.backend.settleTransport()

            #expect(assembly.backend.state == .idle,
                    ".idle was not honest: state is \(assembly.backend.state)")
            let stopped = await assembly.backend.domainSnapshotForTesting
            #expect(stopped.isPlaying == false)
            #expect(stopped.poolInFlight == 0, "buffers stayed out of the pool")
            #expect(stopped.poolAvailable == stopped.poolCapacity,
                    "pool recovered \(stopped.poolAvailable) of \(stopped.poolCapacity)")
            #expect(stopped.liveSources == 0, "sources stayed live")
            #expect(stopped.activeConverters == 0, "converters stayed live")
            #expect(stopped.openFiles == 0, "files stayed open")
            #expect(stopped.scheduledSegments == 0, "segments survived the teardown")
            #expect(stopped.unreconciledDeposits == 0, "recycle tokens were left unreconciled")
            #expect(stopped.accountingBalances)

            // A late wakeup from the dead session finds nothing to do.
            if let domain = assembly.backend.audioDomain {
                for _ in 0..<3 { await domain.refill() }
            }
            let afterLate = await assembly.backend.domainSnapshotForTesting
            #expect(afterLate.chunksScheduled == stopped.chunksScheduled,
                    "a late wakeup scheduled \(afterLate.chunksScheduled - stopped.chunksScheduled) chunks after stop")
            #expect(afterLate.poolInFlight == 0, "a late wakeup took pool buffers after stop")
            #expect(afterLate.isPlaying == false, "a late wakeup restarted playback")
        }
    }

    /// A schedule batch captured against a tail that a stop has since replaced is refused whole —
    /// the fence that stops work suspended across a teardown from landing in the next session.
    @Test func aBatchFromASupersededTailCannotSchedule() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["f0", "f1"], frames: 441_000, in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            assembly.session.replaceQueue(songIDs: ["f0"])
            try await assembly.controller.play()
            await driveUntilRendering(assembly.controller)

            // What an in-flight replenish would have captured before the stop.
            let staleTail = assembly.backend.cachedReadout.tailGeneration

            assembly.controller.stop()
            await assembly.backend.settleTransport()
            let stopped = await assembly.backend.domainSnapshotForTesting

            let late = try GaplessTrackPreparer.describe(
                trackID: "f1", fileURL: files["f1"]!, renderSampleRate: Self.sampleRate)
            await #expect(throws: GaplessEngineFailure.scheduleSuperseded) {
                try await assembly.backend.schedule(
                    [(late, GaplessQueueItemID(rawValue: 99), 1)],
                    expectedTailGeneration: staleTail)
            }
            let after = await assembly.backend.domainSnapshotForTesting
            #expect(after.liveSources == 0, "the refused batch still opened a source")
            #expect(after.chunksScheduled == stopped.chunksScheduled,
                    "the refused batch still scheduled audio")
        }
    }

    // MARK: - Single-owner production proof

    /// Every production player-node mutation — scheduleBuffer, play, pause, stop — executes inside
    /// the audio domain, driven end to end through the production controller.
    ///
    /// The compiler proves the domain's methods are actor-isolated; this pins that the production
    /// transport path actually reaches them, so a future change that mutates the node from the
    /// backend again stops being recorded here and fails.
    @Test func everyProductionPlayerMutationRunsThroughTheAudioDomain() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["o0"], frames: 441_000, in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            assembly.session.replaceQueue(songIDs: ["o0"])
            try await assembly.controller.play()
            await driveUntilRendering(assembly.controller)

            assembly.controller.pause()
            await assembly.backend.settleTransport()
            try assembly.controller.resume()
            await assembly.backend.settleTransport()
            assembly.controller.stop()
            await assembly.backend.settleTransport()

            let domain = try #require(assembly.backend.audioDomain,
                                      "production never constructed its domain")
            let operations = await domain.playerOperations
            #expect(operations.contains(.scheduleBuffer),
                    "no production scheduleBuffer went through the domain")
            #expect(operations.contains(.play), "no production play went through the domain")
            #expect(operations.contains(.pause), "no production pause went through the domain")
            #expect(operations.contains(.stop), "no production stop went through the domain")
        }
    }
}
