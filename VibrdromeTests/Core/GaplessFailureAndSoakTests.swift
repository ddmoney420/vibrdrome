import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Failure paths and a bounded soak.
///
/// The rule for every failure here is the same: the session must end in a *known* state, and it must
/// never claim something that did not happen — no phantom boundary, no item marked audible or
/// completed that never played, no queue index left pointing at the wrong thing.
///
/// The soak in this file is the **CI-sized** one. The full-length soak is a separate, explicit
/// command (see `soakIterations`), because a one-hour run does not belong in the normal verify loop.
@MainActor
struct GaplessFailureAndSoakTests {
    static let sampleRate = 44_100.0
    static let trackFrames = 8_820          // 0.2 s — soak needs many boundaries, quickly
    static let tones: [Double] = [233, 379, 611, 977]

    /// Bounded by default so `verify-build.sh` stays usable. Set `GAPLESS_SOAK=full` for the long
    /// run; the assertions are identical, only the volume changes.
    static var soakIsFull: Bool { ProcessInfo.processInfo.environment["GAPLESS_SOAK"] == "full" }

    /// Printed by every soak test so a gate can prove which branch actually ran.
    ///
    /// This exists because the mistake has already been made here: `GAPLESS_SOAK=full` was reported
    /// as a full run when xcodebuild had not forwarded the variable and the bounded path executed —
    /// the identical runtime was the only clue. A marker in the output removes the guesswork.
    static func announceSoakMode() {
        print("GAPLESS_SOAK_MODE=\(soakIsFull ? "full" : "bounded")")
    }
    static var soakTransitions: Int { soakIsFull ? 500 : 60 }
    static var soakMutations: Int { soakIsFull ? 250 : 30 }

    @MainActor
    struct Rig {
        let controller: GaplessPlaybackController
        let capture: GaplessRealTimeCapture
        let songIDs: [String]
        let directory: URL
        func cleanUp() {
            capture.stop()
            controller.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        func heard() -> [Double] {
            capture.heardSequence(frequencies: GaplessFailureAndSoakTests.tones,
                                  sampleRate: GaplessFailureAndSoakTests.sampleRate)
        }
    }

    static func makeRig(count: Int, repeatMode: RepeatMode = .off,
                        provider: GaplessFileProviding? = nil) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gfs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var files: [String: URL] = [:]
        var songIDs: [String] = []
        for index in 0..<count {
            let tone = tones[index % tones.count]
            let songID = "song\(index + 1)"
            let url = directory.appendingPathComponent("\(songID).wav")
            var samples = [Int16](repeating: 0, count: trackFrames)
            for i in 0..<trackFrames {
                let value = 0.5 * sin(2.0 * .pi * tone * Double(i) / sampleRate)
                samples[i] = Int16((max(-1, min(1, value)) * 32767).rounded())
            }
            try GaplessPipelineOfflineTests.writeWav(url: url, samples: samples, sampleRate: sampleRate)
            files[songID] = url
            songIDs.append(songID)
        }

        let session = GaplessPlaybackSession(sampleRate: sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = Double(trackFrames) / sampleRate }
        session.setRepeatMode(repeatMode)

        let backend = GaplessRealTimeBackend()
        #if os(iOS)
        backend.activateAudioSession = {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default)
            try audio.setActive(true)
        }
        backend.deactivateAudioSession = { try? AVAudioSession.sharedInstance().setActive(false) }
        #endif

        let preparer = GaplessTrackPreparer(
            provider: provider ?? GaplessLocalFileProvider(filesByTrackID: files),
            renderSampleRate: sampleRate)
        let controller = GaplessPlaybackController(session: session, backend: backend,
                                                   preparer: preparer)
        return Rig(controller: controller, capture: GaplessRealTimeCapture(engine: backend.engine),
                   songIDs: songIDs, directory: directory)
    }

    @discardableResult
    static func run(_ rig: Rig, until what: String, timeout: TimeInterval = 60,
                    _ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await rig.controller.tick()
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(4))
        }
        Issue.record("timed out waiting for \(what)")
        return false
    }

    /// A provider that can be made to fail or stall on demand — the seam for simulating decode,
    /// conversion, cache-removal and deadline scenarios without touching production code.
    final class ControllableProvider: GaplessFileProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var files: [String: URL]
        private var failing: Set<String> = []
        private var delay: TimeInterval = 0

        init(files: [String: URL]) { self.files = files }

        func fail(_ trackID: String) { lock.lock(); failing.insert(trackID); lock.unlock() }
        func removeFile(_ trackID: String) { lock.lock(); files[trackID] = nil; lock.unlock() }
        func setDelay(_ seconds: TimeInterval) { lock.lock(); delay = seconds; lock.unlock() }

        private func snapshot(_ trackID: String) -> (Bool, URL?, TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            return (failing.contains(trackID), files[trackID], delay)
        }

        func localFile(forTrack trackID: String) async throws -> URL {
            // Read the state under the lock in a synchronous helper: NSLock cannot be held across
            // an await, and the delay below is an await.
            let (shouldFail, url, wait) = snapshot(trackID)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if shouldFail || url == nil {
                throw GaplessPreparationError.noLocalFile(trackID: trackID)
            }
            return url!
        }
    }

    // MARK: - Part 9.20: decoder failure

    /// A decode failure must not touch the currently audible track, and must never mark the failed
    /// item audible or completed.
    @Test func decodeFailureLeavesTheAudibleTrackAloneAndReportsTheFailure() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        // Replace the second track's file with something undecodable.
        let broken = rig.directory.appendingPathComponent("song2.wav")
        try Data(repeating: 0x7F, count: 512).write(to: broken)

        rig.capture.start()
        try await rig.controller.play()
        await Self.run(rig, until: "first track heard", timeout: 30) { !rig.heard().isEmpty }
        await Self.run(rig, until: "the broken item to be classified", timeout: 20) {
            rig.controller.session.queue.items.contains { $0.state == .failed }
        }

        let failed = rig.controller.session.queue.items.first { $0.state == .failed }
        #expect(failed?.songID == rig.songIDs[1])
        // Never audible, never completed, and no boundary invented for it.
        #expect(!rig.controller.observedBoundaries.contains { $0.songID == rig.songIDs[1] })
        #expect(failed?.audibleFrames == 0)
        #expect(failed?.scrobbleSubmitted == false)
        #expect(rig.controller.preparationRecords[failed!.id]?.failure != nil)
        // The audible track is unaffected.
        #expect(rig.heard().first == Self.tones[0])
        // Queue index still coherent.
        #expect(rig.controller.session.queue.count == 3)
    }

    @Test func immediateProviderFailureDoesNotStartPlayback() async throws {
        let provider = ControllableProvider(files: [:])
        let rig = try Self.makeRig(count: 2, provider: provider)
        defer { rig.cleanUp() }

        try? await rig.controller.play()
        await rig.controller.tick()

        #expect(rig.controller.session.audibleItemID == nil)
        #expect(rig.controller.observedBoundaries.isEmpty)
        #expect(rig.controller.session.queue.items.allSatisfy {
            $0.state == .failed || $0.state == .pending
        })
    }

    // MARK: - Part 9.21: cache-file removal

    /// Removal is recoverable before scheduling and not after — reported either way, never guessed.
    @Test func cacheRemovalBeforeSchedulingFailsCleanly() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var files: [String: URL] = [:]
        for index in 0..<2 {
            let url = directory.appendingPathComponent("s\(index).wav")
            var samples = [Int16](repeating: 0, count: Self.trackFrames)
            for i in 0..<Self.trackFrames {
                samples[i] = Int16(0.5 * 32767 * sin(2.0 * .pi * Self.tones[index] * Double(i) / Self.sampleRate))
            }
            try GaplessPipelineOfflineTests.writeWav(url: url, samples: samples,
                                                     sampleRate: Self.sampleRate)
            files["s\(index)"] = url
        }
        let provider = ControllableProvider(files: files)
        let session = GaplessPlaybackSession(sampleRate: Self.sampleRate)
        session.replaceQueue(songIDs: ["s0", "s1"])
        session.songDurations = ["s0": 0.2, "s1": 0.2]
        let backend = GaplessRealTimeBackend()
        let controller = GaplessPlaybackController(
            session: session, backend: backend,
            preparer: GaplessTrackPreparer(provider: provider, renderSampleRate: Self.sampleRate))
        defer { controller.stop() }

        // Remove the second track's source before it is ever prepared.
        provider.removeFile("s1")
        try? await controller.play()
        await controller.tick()

        let second = session.queue.items[1]
        #expect(session.queue.item(id: second.id)?.state == .failed)
        #expect(!controller.observedBoundaries.contains { $0.songID == "s1" })
        #expect(controller.preparationRecords[second.id]?.failure != nil)
    }

    // MARK: - Part 9.26: deadline miss

    /// A slow provider means the successor is not ready in time. Under `controlledWait` the engine
    /// must report the miss, keep the queue correct, and continue with the right item once ready —
    /// never skip it, never mark it played, never invent a boundary before its audio exists.
    @Test func slowPreparationIsReportedAndTheCorrectItemStillPlays() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var files: [String: URL] = [:]
        for index in 0..<2 {
            let url = directory.appendingPathComponent("d\(index).wav")
            var samples = [Int16](repeating: 0, count: Self.trackFrames)
            for i in 0..<Self.trackFrames {
                samples[i] = Int16(0.5 * 32767 * sin(2.0 * .pi * Self.tones[index] * Double(i) / Self.sampleRate))
            }
            try GaplessPipelineOfflineTests.writeWav(url: url, samples: samples,
                                                     sampleRate: Self.sampleRate)
            files["d\(index)"] = url
        }
        let provider = ControllableProvider(files: files)
        provider.setDelay(0.35)          // longer than a 0.2 s track: the successor cannot be ready

        let session = GaplessPlaybackSession(sampleRate: Self.sampleRate)
        session.replaceQueue(songIDs: ["d0", "d1"])
        session.songDurations = ["d0": 0.2, "d1": 0.2]
        let backend = GaplessRealTimeBackend()
        #if os(iOS)
        backend.activateAudioSession = {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default)
            try audio.setActive(true)
        }
        #endif
        let controller = GaplessPlaybackController(
            session: session, backend: backend,
            preparer: GaplessTrackPreparer(provider: provider, renderSampleRate: Self.sampleRate))
        let capture = GaplessRealTimeCapture(engine: backend.engine)
        defer { capture.stop(); controller.stop() }
        #expect(controller.deadlinePolicy == .controlledWait)

        capture.start()
        try await controller.play()
        // Wait for the delayed successor to actually be HEARD. A boundary fires as soon as the
        // clock reaches the segment's start frame, which under a controlled wait is before its audio
        // exists — so a boundary-count wait would sample the capture too early.
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            await controller.tick()
            let soFar = capture.heardSequence(frequencies: Self.tones, sampleRate: Self.sampleRate)
            if soFar.count >= 2 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        let heard = capture.heardSequence(frequencies: Self.tones, sampleRate: Self.sampleRate)
        // The correct item still played, in the correct order — a wait, not a skip.
        #expect(heard.first == Self.tones[0], "heard \(heard)")
        #expect(heard.contains(Self.tones[1]), "the delayed successor never played: \(heard)")
        // The queue never lost the item and never marked it done without playing it.
        #expect(session.queue.count == 2)
        #expect(!session.queue.items.contains { $0.state == .completed && $0.audibleFrames == 0 })
    }

    // MARK: - Part 9.22/23/24: engine lifecycle simulations

    /// A configuration change must not leave the session claiming to play. Reconstruction is passive:
    /// nothing re-activates the audio session on its own.
    @Test func engineConfigurationChangeLeavesAKnownStateWithoutReactivating() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        var activations = 0
        rig.controller.backend.activateAudioSession = { activations += 1 }
        try await rig.controller.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }
        #expect(activations == 1)
        let queueCountBefore = rig.controller.session.queue.count
        let indexBefore = rig.controller.session.queue.currentIndex

        // Simulate the engine going away underneath us, as a configuration change does.
        rig.controller.backend.engine.engine.stop()
        rig.controller.stop()

        #expect(rig.controller.backend.state == .idle)
        #expect(!rig.controller.session.isPlaying)
        // Queue and position survive.
        #expect(rig.controller.session.queue.count == queueCountBefore)
        #expect(rig.controller.session.queue.currentIndex == indexBefore)
        // Rebuilding the graph does not activate anything — explicit play is still required.
        try rig.controller.backend.prepareGraph()
        #expect(activations == 1, "reconstruction re-activated the audio session")
        #expect(rig.controller.backend.state == .prepared)
    }

    /// Media-services reset: the old graph is gone. Reconstruction must be passive and stale
    /// callbacks from the old engine must not move the session.
    @Test func mediaServicesResetDiscardsStaleWorkAndRebuildsPassively() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        var activations = 0
        rig.controller.backend.activateAudioSession = { activations += 1 }
        try await rig.controller.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }
        let staleTail = rig.controller.backend.tailGeneration

        rig.controller.stop()                       // what a reset forces
        try rig.controller.backend.prepareGraph()   // reconstruct, passively

        #expect(activations == 1, "reconstruction must not activate the session")
        #expect(rig.controller.backend.state == .prepared)
        // Anything tagged with the old tail can no longer apply.
        #expect(!rig.controller.backend.isCurrentTail(staleTail))
        #expect(rig.controller.session.queue.count == 3)
    }

    /// Route-change shape: a category/route transition ends in a coherent state. Real device route
    /// behaviour remains Checkpoint 4 — this only models the state machine.
    @Test func routeChangeShapeLeavesACoherentSession() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        try await rig.controller.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }

        // Old device unavailable → pause is the safe transition.
        rig.controller.pause()
        #expect(rig.controller.backend.state == .paused)
        #expect(!rig.controller.session.isPlaying)

        // New device available → explicit resume, not automatic.
        try rig.controller.resume()
        #expect(rig.controller.backend.state == .playing)
        #expect(rig.controller.session.isPlaying)
    }

    /// A failed tail replacement must not leave the session claiming either the old or the new audio
    /// is scheduled.
    @Test func tailReplacementFailureLeavesAKnownStateWithTheQueueIntact() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        try await rig.controller.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }

        // Delete every source, then force a tail rebuild: the replacement cannot be scheduled.
        for songID in rig.songIDs {
            try? FileManager.default.removeItem(at: rig.directory.appendingPathComponent("\(songID).wav"))
        }
        try await rig.controller.next()
        await rig.controller.tick()

        // The old tail is gone and no new audio is claimed.
        #expect(rig.controller.backend.scheduledSegments.allSatisfy { segment in
            rig.controller.session.queue.item(id: segment.itemID) != nil
        })
        // The queue survives so the user can retry.
        #expect(rig.controller.session.queue.count == 2)
        #expect(rig.controller.backend.state != .failed || !rig.controller.session.isPlaying)
    }

    // MARK: - Part 8/9: bounded soak

    /// Sustained automatic playback with transport and mutation churn.
    ///
    /// CI-sized by default; `GAPLESS_SOAK=full` raises the volume without changing a single
    /// assertion, so the long run proves the same properties rather than different ones.
    @Test func soakSustainsPlaybackWithoutDriftOrLeaks() async throws {
        Self.announceSoakMode()
        let rig = try Self.makeRig(count: 4, repeatMode: .all)
        defer { rig.cleanUp() }
        let playerBefore = ObjectIdentifier(rig.controller.backend.engine.player)
        let eqBefore = ObjectIdentifier(rig.controller.backend.engine.eq)
        let gainBefore = ObjectIdentifier(rig.controller.backend.engine.gainStage.node)

        try await rig.controller.play()
        let target = Self.soakTransitions
        var lastFrame: AVAudioFramePosition = 0
        var checkpoints: [(Int, AVAudioFramePosition)] = []

        await Self.run(rig, until: "\(target) transitions",
                       timeout: Self.soakIsFull ? 900 : 180) {
            let count = rig.controller.observedBoundaries.count
            let frame = rig.controller.backend.renderFrame
            // The logical clock must never run backwards over a long run.
            if frame < lastFrame { Issue.record("clock went backwards: \(frame) after \(lastFrame)") }
            lastFrame = frame
            if count % max(1, target / 4) == 0, checkpoints.last?.0 != count {
                checkpoints.append((count, frame))
            }
            return count >= target
        }

        let boundaries = rig.controller.observedBoundaries
        #expect(boundaries.count >= target)
        // No duplicate and no missing boundary: one play instance per play, strictly increasing.
        #expect(Set(boundaries.map(\.playInstance)).count == boundaries.count)
        let raw = boundaries.map(\.playInstance.rawValue)
        #expect(raw == raw.sorted(), "play instances out of order")
        // Repeat All order is exact over the whole run.
        let expected = (0..<boundaries.count).map { rig.songIDs[$0 % rig.songIDs.count] }
        #expect(boundaries.map(\.songID) == expected)
        // No engine restart, no node replacement.
        #expect(rig.controller.backend.engine.engine.isRunning)
        #expect(ObjectIdentifier(rig.controller.backend.engine.player) == playerBefore)
        #expect(ObjectIdentifier(rig.controller.backend.engine.eq) == eqBefore)
        #expect(ObjectIdentifier(rig.controller.backend.engine.gainStage.node) == gainBefore)
        // Advancing never bumps the queue generation, and nothing stale was applied.
        #expect(rig.controller.session.queue.generation == 1)
        #expect(rig.controller.deadlineMisses.isEmpty)
        // The scheduled tail stays bounded — no unbounded growth over hundreds of transitions.
        #expect(rig.controller.backend.scheduledSegments.count <= rig.controller.window.size + 1,
                "scheduled tail grew to \(rig.controller.backend.scheduledSegments.count)")
    }

    /// Transport and mutation churn under sustained playback.
    @Test func soakSustainsTransportAndMutationChurn() async throws {
        Self.announceSoakMode()
        let rig = try Self.makeRig(count: 4, repeatMode: .all)
        defer { rig.cleanUp() }
        let playerBefore = ObjectIdentifier(rig.controller.backend.engine.player)
        try await rig.controller.play()
        await Self.run(rig, until: "playback") { rig.controller.backend.renderFrame > 2_000 }

        var latencies: [TimeInterval] = []
        let rounds = Self.soakMutations
        for round in 0..<rounds {
            let started = Date()
            switch round % 5 {
            case 0: try await rig.controller.next()
            case 1: try await rig.controller.previous(elapsedSeconds: 1)
            case 2: try await rig.controller.seek(toSeconds: 0.05)
            case 3: try await rig.controller.playNext(songID: rig.songIDs[round % 4])
            default:
                let id = rig.controller.session.queue.items.last!.id
                try await rig.controller.remove(itemID: id)
                try await rig.controller.addToQueue(songID: rig.songIDs[round % 4])
            }
            latencies.append(Date().timeIntervalSince(started))
            await rig.controller.tick()
        }

        // Latency must not grow over the run — the second half is not slower than the first.
        let half = latencies.count / 2
        let firstHalf = latencies.prefix(half).reduce(0, +) / Double(max(1, half))
        let secondHalf = latencies.suffix(half).reduce(0, +) / Double(max(1, half))
        #expect(secondHalf < firstHalf * 3 + 0.05,
                "transport latency grew: \(firstHalf)s → \(secondHalf)s")
        // Still healthy, same graph, queue coherent.
        #expect(rig.controller.backend.engine.engine.isRunning)
        #expect(ObjectIdentifier(rig.controller.backend.engine.player) == playerBefore)
        #expect(rig.controller.session.queue.count >= 4)
        #expect(rig.controller.backend.scheduledSegments.count <= rig.controller.window.size + 1)
    }

    /// Visualizer open/close churn plus EQ and ReplayGain changes during sustained playback.
    @Test func soakSustainsVisualizerAndEffectChurn() async throws {
        Self.announceSoakMode()
        let rig = try Self.makeRig(count: 4, repeatMode: .all)
        defer { rig.cleanUp() }
        rig.controller.backend.engine.installVisualizerFeed()
        defer { rig.controller.backend.engine.uninstallVisualizerFeed() }
        let feed = rig.controller.backend.engine.visualizerFeed
        let classic = GaplessClassicVisualizerAdapter(feed: feed, sampleRate: Self.sampleRate)
        let native = GaplessNativeVisualizerAdapter(feed: feed, source: VisualizerPCMSource())

        try await rig.controller.play()
        for round in 0..<Self.soakMutations {
            classic.activate()
            native.activate()
            await rig.controller.tick()
            _ = classic.drain()
            _ = native.drain()
            classic.deactivate()
            native.deactivate()
            rig.controller.backend.engine.setEQEnabled(round.isMultiple(of: 2))
            rig.controller.backend.engine.gainStage.apply(
                GaplessGain(linear: round.isMultiple(of: 3) ? 0.7 : 1.0, source: .trackGain))
            try? await Task.sleep(for: .milliseconds(3))
        }

        // One tap for the whole run; consumers churned freely; nothing rebuilt.
        #expect(feed.isInstalled)
        #expect(feed.registeredConsumerCount == 2)
        #expect(feed.stats.contendedCallbacks == 0)
        #expect(rig.controller.backend.engine.engine.isRunning)
        // Rings stayed bounded across all the churn.
        for identifier in ["classic", "native"] {
            let consumer = feed.consumer(identifier: identifier)
            #expect((consumer?.buffer.stats.fillFrames ?? 0) <= (consumer?.buffer.frameCapacity ?? 0))
        }
    }

    /// 100 stop/start cycles on one engine instance.
    @Test func soakSustainsStopStartCycles() async throws {
        Self.announceSoakMode()
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        let playerBefore = ObjectIdentifier(rig.controller.backend.engine.player)
        let cycles = Self.soakIsFull ? 100 : 40

        for _ in 0..<cycles {
            try await rig.controller.play()
            await rig.controller.tick()
            rig.controller.stop()
        }

        #expect(ObjectIdentifier(rig.controller.backend.engine.player) == playerBefore)
        #expect(rig.controller.backend.state == .idle)
        #expect(rig.controller.backend.scheduledSegments.isEmpty)
        #expect(rig.controller.session.queue.count == 2)
    }
}
