import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// The isolated Persistent audio domain: PCM production that does not depend on the main actor.
///
/// **What this suite is for.** Production's `GaplessRealTimeBackend` still owns a main-actor
/// scheduler, and a measured 1 s main-actor stall starves it — four render-side recycle deposits
/// where continuous playback needed eleven. That is the click-and-pause heard on device when the
/// app is backgrounded. `GaplessAudioDomain` is the replacement, and this suite proves it over a
/// **real** `AVAudioEngine`, a real player node and real decodable media, with nothing from the
/// production backend involved.
///
/// **Evidence rule.** Continuity is judged on render-side recycle deposits, never on `renderFrame`
/// — that clock is already proven to advance through silence, and `inFlightChunks` is main-actor
/// bookkeeping that simply freezes when the main actor cannot run. The inbox is written by the
/// render thread under its own lock, so it is the one signal a stalled main actor cannot distort.
@Suite(.serialized)
@MainActor
struct GaplessAudioDomainTests {

    private static let sampleRate = GaplessBufferFixtures.sampleRate
    /// Long enough that the media itself can never be why rendering stops.
    private static let trackFrames = 882_000   // 20 s

    // MARK: - Harness

    /// A real graph, started the way the application starts one, handed to the domain for
    /// scheduling and player mutation.
    private final class Harness {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()
        let format = GaplessRenderFormat.standard

        init() {
            engine.attach(player)
            engine.attach(mixer)
            engine.connect(player, to: mixer, format: format)
            engine.connect(mixer, to: engine.mainMixerNode, format: format)
        }

        var handle: GaplessGraphHandle {
            GaplessGraphHandle(engine: engine, player: player, renderFormat: format)
        }

        /// Application-side startup: the engine must be running before the node may play, which is
        /// the ordering the domain deliberately does not own.
        func startEngine() throws {
            engine.prepare()
            try engine.start()
        }

        func stopEngine() {
            player.stop()
            engine.stop()
        }
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("domain-\(UInt64.random(in: 0..<UInt64.max))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func makeTrack(id: String, in directory: URL,
                           sampleRate: Double = sampleRate) throws -> GaplessPreparedTrack {
        let url = directory.appendingPathComponent("\(id).wav")
        try GaplessBufferFixtures.writeStereoWav(
            url: url, frequency: 440, frames: Self.trackFrames, sampleRate: sampleRate)
        return try GaplessTrackPreparer.describe(trackID: id, fileURL: url,
                                                 renderSampleRate: Self.sampleRate)
    }

    private func itemID(_ raw: UInt64) -> GaplessQueueItemID { GaplessQueueItemID(rawValue: raw) }

    /// Hold the main actor, exactly as a background throttle does. Synchronous on purpose: an
    /// `await` would yield and let the very work under test run.
    private func blockMainActor(milliseconds: Int) {
        let deadline = Date().addingTimeInterval(Double(milliseconds) / 1000)
        while Date() < deadline { /* the main actor must be unavailable */ }
    }

    /// Start a domain playing real audio and return it with its harness.
    private func startPlaying(in directory: URL, trackID: String = "d0")
        async throws -> (Harness, GaplessAudioDomain) {
        let harness = Harness()
        let track = try makeTrack(id: trackID, in: directory)
        try harness.startEngine()
        let domain = await GaplessAudioDomain(graph: harness.handle)
        try await domain.enqueue(track: track, itemID: itemID(1), generation: 1)
        await domain.play()
        return (harness, domain)
    }

    // MARK: - Real PCM over a real graph

    /// The domain schedules real PCM, reaches its target depth, plays, recycles and refills.
    @Test func theDomainSchedulesRealPCMAndKeepsItsDepth() async throws {
        try await withTemporaryDirectory { directory in
            let (harness, domain) = try await startPlaying(in: directory)
            defer { harness.stopEngine() }

            var snapshot = await domain.snapshot()
            #expect(snapshot.isPlaying, "the domain did not start the node")
            #expect(snapshot.scheduledDepth > 0, "nothing was scheduled")
            #expect(snapshot.liveSources == 1)
            #expect(snapshot.poolInFlight > 0, "no pool buffers were handed to the node")

            // Let real rendering recycle real buffers, without ticking anything.
            try? await Task.sleep(for: .milliseconds(600))
            snapshot = await domain.snapshot()

            #expect(snapshot.renderDeposits > 0,
                    "the render thread never reported finishing a buffer")
            #expect(snapshot.chunksScheduled > snapshot.poolCapacity,
                    "no replacement buffers were produced: scheduled \(snapshot.chunksScheduled)")
            #expect(snapshot.poolInFlight <= snapshot.poolCapacity, "pool over-committed")
            #expect(snapshot.poolAvailable + snapshot.poolInFlight == snapshot.poolCapacity,
                    "pool accounting broken: \(snapshot.poolAvailable)+\(snapshot.poolInFlight) of \(snapshot.poolCapacity)")
            #expect(snapshot.accountingBalances, "chunk ledger does not reconcile")
            #expect(snapshot.poolStarvations == 0, "the pool starved while the main actor was free")
        }
    }

    // MARK: - The acceptance criterion

    /// PCM keeps being supplied while the main actor is unavailable, up to five seconds.
    ///
    /// This is the whole point of the domain. Judged on render-side deposits and on replacement
    /// chunks actually produced during the stall — the main actor is blocked throughout, so no
    /// main-actor bookkeeping could have updated even if it wanted to.
    @Test func pcmIsSuppliedWhileTheMainActorIsBlocked() async throws {
        try await withTemporaryDirectory { directory in
            let (harness, domain) = try await startPlaying(in: directory)
            defer { harness.stopEngine() }
            try? await Task.sleep(for: .milliseconds(300))

            var rows: [String] = []
            var allSupplied = true

            for window in [100, 250, 500, 1_000, 2_000, 5_000] {
                let before = await domain.snapshot()
                let startedAt = Date()

                blockMainActor(milliseconds: window)

                let elapsed = Date().timeIntervalSince(startedAt)
                let after = await domain.snapshot()

                let deposits = after.renderDeposits - before.renderDeposits
                let produced = after.chunksScheduled - before.chunksScheduled
                // What a continuously-rendering node consumes in that much wall time.
                let needed = Int((elapsed * Self.sampleRate / 4_096).rounded())
                // Supplied means the node kept being fed: it reported finishing roughly what it
                // needed, and replacements were produced to match. Without refill it can only ever
                // report the four chunks it already held.
                let supplied = deposits >= needed - 1 && produced >= needed - 1
                allSupplied = allSupplied && supplied

                rows.append(String(
                    format: "stall %5d ms -> deposits %3d, produced %3d, needed %3d, "
                          + "depth %d, pool %d/%d -> %@",
                    window, deposits, produced, needed, after.scheduledDepth,
                    after.poolAvailable, after.poolCapacity, supplied ? "SUPPLIED" : "STARVED"))

                #expect(after.poolAvailable + after.poolInFlight == after.poolCapacity,
                        "pool accounting broke during a \(window) ms stall")
                #expect(after.accountingBalances, "chunk ledger broke during a \(window) ms stall")
                #expect(after.poolStarvations == 0,
                        "the pool starved during a \(window) ms stall")

                // Recover fully before the next window.
                try? await Task.sleep(for: .milliseconds(300))
            }

            for row in rows { print("DOMAIN \(row)") }
            #expect(allSupplied, "the domain starved while the main actor was blocked")
        }
    }

    /// Deposits are reconciled exactly once even though wakeups coalesce.
    ///
    /// Many render completions can land while one refill is already queued; the inbox drains them
    /// as a batch. What must never happen is a token going unreconciled — that would mean a buffer
    /// the pool believes is still out.
    @Test func everyRenderDepositIsReconciledExactlyOnce() async throws {
        try await withTemporaryDirectory { directory in
            let (harness, domain) = try await startPlaying(in: directory)
            defer { harness.stopEngine() }

            try? await Task.sleep(for: .milliseconds(800))

            // Sampled while running: `stopAndReset` clears the inbox, counter included, so the
            // evidence that recycling happened has to be taken before the teardown that proves it
            // was reconciled.
            let running = await domain.snapshot()
            #expect(running.renderDeposits > 0, "nothing was ever recycled")
            #expect(running.unreconciledDeposits == 0,
                    "\(running.unreconciledDeposits) recycle tokens were unreconciled while running")

            await domain.stopAndReset()
            let stopped = await domain.snapshot()

            #expect(stopped.unreconciledDeposits == 0,
                    "\(stopped.unreconciledDeposits) recycle tokens survived teardown")
            #expect(stopped.poolAvailable == stopped.poolCapacity,
                    "a token went missing: pool recovered \(stopped.poolAvailable) of \(stopped.poolCapacity)")
            #expect(stopped.accountingBalances,
                    "chunks scheduled did not reconcile against recycled + reclaimed")
        }
    }

    // MARK: - Single-owner proof

    /// Every player-node mutation the domain performs runs under `GaplessAudioActor`.
    ///
    /// The compiler is the real proof — every method that touches the node is isolated, so a call
    /// from anywhere else would not build. This test pins the *observable* half: the recorded
    /// operations exist and were produced through the actor, so if one of them is ever moved out
    /// from behind the isolation, it stops being recorded here.
    @Test func everyPlayerMutationRunsOnTheAudioActor() async throws {
        try await withTemporaryDirectory { directory in
            let (harness, domain) = try await startPlaying(in: directory)
            defer { harness.stopEngine() }
            try? await Task.sleep(for: .milliseconds(200))

            await domain.pause()
            await domain.resume()
            await domain.stopAndReset()

            let operations = await domain.playerOperations
            #expect(operations.contains(.scheduleBuffer), "no scheduleBuffer was recorded")
            #expect(operations.contains(.play), "no play was recorded")
            #expect(operations.contains(.pause), "no pause was recorded")
            #expect(operations.contains(.stop), "no stop was recorded")

            // Reading them requires entering the actor; that is the isolation being demonstrated.
            let reread = await GaplessAudioActor.shared.run { await domain.playerOperations }
            #expect(reread == operations)
        }
    }

    // MARK: - Pause and resume

    /// Pause and resume keep the same domain, the same scheduler and the same pool.
    @Test func pauseAndResumeKeepOneSessionAndLeakNothing() async throws {
        try await withTemporaryDirectory { directory in
            let (harness, domain) = try await startPlaying(in: directory)
            defer { harness.stopEngine() }
            try? await Task.sleep(for: .milliseconds(300))
            let before = await domain.snapshot()

            await domain.pause()
            let paused = await domain.snapshot()
            #expect(paused.isPlaying == false, "pause did not stop the node")
            #expect(paused.liveSources == before.liveSources, "pause tore down the source")
            #expect(paused.scheduledSegments == before.scheduledSegments,
                    "pause discarded the scheduled tail")
            #expect(paused.poolAvailable + paused.poolInFlight == paused.poolCapacity,
                    "pause leaked pool buffers")

            await domain.resume()
            try? await Task.sleep(for: .milliseconds(400))
            let resumed = await domain.snapshot()

            #expect(resumed.isPlaying, "resume did not restart the node")
            #expect(resumed.liveSources == before.liveSources, "resume rebuilt the source")
            #expect(resumed.renderDeposits > paused.renderDeposits,
                    "refill did not resume after resume")
            #expect(resumed.poolAvailable + resumed.poolInFlight == resumed.poolCapacity,
                    "resume leaked pool buffers")
        }
    }

    // MARK: - Stop, reset and reuse

    /// `stopAndReset` releases everything, and the same domain starts a second session afterwards.
    @Test func stopAndResetReleasesEverythingAndTheDomainIsReusable() async throws {
        try await withTemporaryDirectory { directory in
            let (harness, domain) = try await startPlaying(in: directory)
            defer { harness.stopEngine() }
            try? await Task.sleep(for: .milliseconds(400))
            let running = await domain.snapshot()
            #expect(running.poolInFlight > 0, "the fixture was not actually scheduling")

            await domain.stopAndReset()
            let stopped = await domain.snapshot()

            #expect(stopped.isPlaying == false)
            #expect(stopped.poolInFlight == 0, "buffers stayed out of the pool")
            #expect(stopped.poolAvailable == stopped.poolCapacity,
                    "pool recovered \(stopped.poolAvailable) of \(stopped.poolCapacity)")
            #expect(stopped.liveSources == 0, "sources stayed live")
            #expect(stopped.activeConverters == 0, "converters stayed live")
            #expect(stopped.openFiles == 0, "files stayed open")
            #expect(stopped.scheduledSegments == 0, "segments survived the reset")
            #expect(stopped.unreconciledDeposits == 0, "recycle tokens were left unreconciled")
            #expect(stopped.accountingBalances)

            // A second session on the SAME domain.
            let second = try makeTrack(id: "d1", in: directory)
            try await domain.enqueue(track: second, itemID: itemID(2), generation: 2)
            await domain.play()
            try? await Task.sleep(for: .milliseconds(500))
            let restarted = await domain.snapshot()

            #expect(restarted.isPlaying, "the domain could not start a second session")
            #expect(restarted.liveSources == 1)
            #expect(restarted.renderDeposits > stopped.renderDeposits,
                    "the second session never rendered")
            #expect(restarted.poolAvailable + restarted.poolInFlight == restarted.poolCapacity)
        }
    }

    /// A late recycle wakeup arriving after teardown schedules nothing.
    @Test func aLateWakeupAfterResetSchedulesNothing() async throws {
        try await withTemporaryDirectory { directory in
            let (harness, domain) = try await startPlaying(in: directory)
            defer { harness.stopEngine() }
            try? await Task.sleep(for: .milliseconds(300))

            await domain.stopAndReset()
            let afterReset = await domain.snapshot()

            // Drive refill directly, exactly as a late wakeup would.
            for _ in 0..<5 { await domain.refill() }
            let afterLate = await domain.snapshot()

            #expect(afterLate.chunksScheduled == afterReset.chunksScheduled,
                    "a refill after reset scheduled \(afterLate.chunksScheduled - afterReset.chunksScheduled) chunks")
            #expect(afterLate.poolInFlight == 0, "a refill after reset took pool buffers")
            #expect(afterLate.isPlaying == false, "a refill after reset restarted playback")
        }
    }
}

extension GaplessAudioActor {
    /// Run a closure on the audio actor. Used by the ownership proof to demonstrate that reading
    /// the domain's records requires entering its isolation.
    func run<T: Sendable>(_ body: @GaplessAudioActor () async -> T) async -> T {
        await body()
    }
}
