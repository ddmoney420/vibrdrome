import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Does PCM continuity survive when the main actor stops running?
///
/// **Why this is the right experiment.** iOS keeps a `UIBackgroundModes: audio` app alive while it
/// plays, but it does not promise that ordinary main-actor work keeps its foreground cadence —
/// timers coalesce and main-thread work is deprioritised. Every part of this engine's refill path is
/// `@MainActor`: `GaplessBufferScheduler` is main-actor isolated, and its recycle inbox reacts to a
/// render-thread deposit with `Task { @MainActor in pump() }`. So the inbox makes refill
/// *event-driven*, not *main-actor-independent* — the distinction that matters here, and one an
/// earlier note in this work got wrong.
///
/// Blocking the main actor synchronously reproduces exactly that condition: the heartbeat task and
/// the inbox's pump task are both unable to run, while the audio render thread keeps pulling. What
/// is measured is not wall clock but **rendered frames against elapsed time** — audio that kept
/// flowing advances the render clock in step with the wall; audio that starved falls behind.
@Suite(.serialized)
@MainActor
struct PersistentBackgroundStarvationTests {

    private static let sampleRate = GaplessBufferFixtures.sampleRate
    /// Long enough that the track itself can never be the reason rendering stops.
    private static let trackFrames = 441_000   // 10 s

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

    private func makeFiles(_ ids: [String], in directory: URL) throws -> [String: URL] {
        var files: [String: URL] = [:]
        for (index, id) in ids.enumerated() {
            let url = directory.appendingPathComponent("\(id).wav")
            try GaplessBufferFixtures.writeStereoWav(
                url: url, frequency: 330 + Double(index) * 110,
                frames: Self.trackFrames, sampleRate: Self.sampleRate)
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

    /// Hold the main actor for `milliseconds`, exactly as a background throttle would.
    ///
    /// Synchronous on purpose: an `await` would yield and let the very tasks under test run, which
    /// would measure nothing.
    private func blockMainActor(milliseconds: Int) {
        let deadline = Date().addingTimeInterval(Double(milliseconds) / 1000)
        while Date() < deadline { /* deliberately spinning: the main actor must be unavailable */ }
    }

    /// One measurement: frames the engine actually rendered while the main actor was unavailable,
    /// against the frames that much wall time should have produced.
    private struct Starvation {
        /// Local copy so the value type is usable without main-actor isolation.
        static let sampleRate = GaplessBufferFixtures.sampleRate
        let blockMilliseconds: Int
        let renderedFrames: AVAudioFramePosition
        let expectedFrames: AVAudioFramePosition
        let inFlightAfter: Int
        /// Buffers the RENDER THREAD reported finishing during the block. Deposited under a lock
        /// from the completion callback, so unlike `inFlightChunks` it is not main-actor
        /// bookkeeping that simply freezes when the main actor cannot run.
        let renderDeposits: Int
        /// Chunks a continuously-rendering node would have consumed in the elapsed time.
        var chunksNeeded: Int { Int((Double(expectedFrames) / 4096).rounded()) }
        /// The node cannot consume more than the ~4 chunks it already held without a refill, so
        /// needing materially more than it reported finishing is starvation, whatever the clock says.
        var starvedOnDeposits: Bool { chunksNeeded > renderDeposits + 1 }
        var deficitFrames: AVAudioFramePosition { max(0, expectedFrames - renderedFrames) }
        var deficitSeconds: Double { Double(deficitFrames) / Self.sampleRate }
        var rendersContinuously: Bool {
            // 25 ms of slack absorbs the render quantum and clock sampling, and is well under the
            // ~372 ms of lead the scheduler holds.
            deficitSeconds < 0.025
        }
        var described: String {
            String(format: "block %4d ms -> rendered %.3f s of %.3f s (deficit %.3f s, in-flight %d)",
                   blockMilliseconds,
                   Double(renderedFrames) / Self.sampleRate,
                   Double(expectedFrames) / Self.sampleRate,
                   deficitSeconds, inFlightAfter)
                + String(format: " | render deposits %d, chunks needed %d -> %@",
                         renderDeposits, chunksNeeded,
                         starvedOnDeposits ? "STARVED" : "supplied")
        }
    }

    private func measure(_ assembly: PersistentPlaybackAssembly,
                         blockMilliseconds: Int) -> Starvation {
        let backend = assembly.backend
        let framesBefore = backend.renderFrame
        let depositsBefore = backend.bufferScheduler.inbox.totalDeposits
        let startedAt = Date()

        blockMainActor(milliseconds: blockMilliseconds)

        let elapsed = Date().timeIntervalSince(startedAt)
        let framesAfter = backend.renderFrame
        return Starvation(
            blockMilliseconds: blockMilliseconds,
            renderedFrames: framesAfter - framesBefore,
            expectedFrames: AVAudioFramePosition(elapsed * Self.sampleRate),
            inFlightAfter: backend.bufferScheduler.inFlightChunks.count,
            renderDeposits: backend.bufferScheduler.inbox.totalDeposits - depositsBefore)
    }

    // MARK: - The dependency, stated as code rather than as a comment

    /// The refill path is main-actor isolated end to end.
    ///
    /// This is the structural half of the diagnosis: the scheduler that produces and schedules every
    /// PCM chunk is `@MainActor`, so a main actor that cannot run is a scheduler that cannot refill,
    /// however the refill was triggered.
    @Test func theRefillPathIsMainActorIsolated() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["m0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            assembly.session.replaceQueue(songIDs: ["m0"])
            try await assembly.controller.play()

            // Reaching any of these off the main actor is a compile error; reaching them here is
            // not. That is the dependency, and it is what background throttling acts on.
            let scheduler = assembly.backend.bufferScheduler
            #expect(scheduler.pool.capacity == 6, "pool capacity changed; the lead calculation below assumes 6")
            let leadSeconds = Double(4 * 4096) / Self.sampleRate
            #expect(abs(leadSeconds - 0.372) < 0.01,
                    "scheduled lead is \(leadSeconds) s — the starvation thresholds assume ~0.372 s")
        }
    }

    // MARK: - The measurement

    /// How long can the main actor be unavailable before audio actually starves?
    ///
    /// Reported for every window so the failure point is data rather than a guess. The assertion is
    /// deliberately weak — this test exists to *characterise*, and the strong assertion lives in
    /// `audioSurvivesAMainActorStallShorterThanTheScheduledLead`.
    @Test func mainActorStallCharacterisation() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["s0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            assembly.session.replaceQueue(songIDs: ["s0"])
            try await assembly.controller.play()
            await driveUntilRendering(assembly.controller)
            #expect(assembly.backend.renderFrame > 0, "the fixture never started rendering")

            var results: [Starvation] = []
            for window in [100, 250, 500, 1_000] {
                results.append(measure(assembly, blockMilliseconds: window))
                // Let the engine recover fully between measurements.
                for _ in 0..<40 {
                    await assembly.controller.tick()
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }

            for result in results { print("STARVATION \(result.described)") }

            let firstStarved = results.first(where: \.starvedOnDeposits)
            print("STARVATION first starved window: "
                  + (firstStarved.map { "\($0.blockMilliseconds) ms" } ?? "none up to 1000 ms"))

            // The render clock is NOT a starvation detector: it advances through silence, and
            // reported a zero deficit for the window the deposit count proves starved. Asserting on
            // it would be the same mistake as reading a position ramp to detect a click.
            if let starved = firstStarved {
                #expect(starved.deficitSeconds < 0.025,
                        "the render clock noticed this starvation, so it is a usable detector after all: \(starved.described)")
            }

            // What must remain true: the node holds ~372 ms of PCM, so a stall well inside that is
            // absorbed. This is the floor the fix must not regress.
            let shortStalls = results.filter { $0.blockMilliseconds <= 250 }
            for result in shortStalls {
                #expect(result.starvedOnDeposits == false,
                        "a stall inside the scheduled lead starved audio: \(result.described)")
            }
            #expect(results.count == 4)
        }
    }

    // MARK: - Does the boundary survive a stall?

    /// Cross a real automatic track boundary while the main actor is unavailable.
    ///
    /// Two different things can starve here and they need separating: the current track's PCM
    /// refill (`pump`), and preparation of the *next* source (`replenishTail`, which opens the file
    /// and builds the converter). If the prefetch window has already enqueued the next track before
    /// the stall begins, the boundary can be sample-continuous even with the main actor frozen —
    /// that is Outcome A, and it means only `pump` needs to move. If it has not, the boundary
    /// starves whatever `pump` does, which is Outcome B.
    @Test func boundaryCharacterisationUnderMainActorStall() async throws {
        try await withTemporaryDirectory { directory in
            let ids = ["b0", "b1", "b2"]
            let files = try makeFiles(ids, in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            assembly.session.replaceQueue(songIDs: ids)
            for id in ids {
                assembly.session.songDurations[id] = Double(Self.trackFrames) / Self.sampleRate
            }
            try await assembly.controller.play()
            await driveUntilRendering(assembly.controller)

            // Let the window fill exactly as production would, then read what is actually ready
            // before the stall — that is the margin the decision rule turns on.
            for _ in 0..<60 {
                await assembly.controller.tick()
                try? await Task.sleep(for: .milliseconds(5))
            }
            let scheduler = assembly.backend.bufferScheduler
            let sourcesReady = scheduler.liveSourceCount
            let segmentsReady = scheduler.segments.count
            let preparedIDs = await assembly.preparer.readyTrackIDs
            print("BOUNDARY before stall: live sources \(sourcesReady), "
                  + "scheduled segments \(segmentsReady), prepared tracks \(preparedIDs.count)")

            for window in [500, 1_000, 2_000] {
                let result = measure(assembly, blockMilliseconds: window)
                print("BOUNDARY \(result.described)")
                for _ in 0..<40 {
                    await assembly.controller.tick()
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }

            let heard = assembly.controller.observedBoundaries.map(\.songID)
            print("BOUNDARY occurrences heard: \(heard)")
            let instances = Set(assembly.controller.observedBoundaries.map(\.playInstance))
            #expect(instances.count == assembly.controller.observedBoundaries.count,
                    "an occurrence reported a boundary twice")
            // Order must never regress even if timing does.
            for (index, songID) in heard.enumerated() where index < ids.count {
                #expect(songID == ids[index],
                        "occurrence \(index) was \(songID), expected \(ids[index]) — order broke")
            }
        }
    }

    /// A stall shorter than the scheduled lead must not starve audio.
    ///
    /// This is the floor the architecture already claims: ~372 ms of PCM is on the node, so a
    /// 100 ms main-actor stall is absorbed entirely by buffers that were already scheduled.
    @Test func audioSurvivesAMainActorStallShorterThanTheScheduledLead() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeFiles(["p0"], in: directory)
            let assembly = makeAssembly(files: files, directory: directory)
            defer { assembly.controller.stop() }
            assembly.session.replaceQueue(songIDs: ["p0"])
            try await assembly.controller.play()
            await driveUntilRendering(assembly.controller)

            let result = measure(assembly, blockMilliseconds: 100)

            #expect(result.rendersContinuously,
                    "a 100 ms main-actor stall already starved audio: \(result.described)")
        }
    }
}
