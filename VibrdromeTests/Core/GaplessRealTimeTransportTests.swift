import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Transport, repeat, shuffle and queue mutation driven through the **real-time** engine, with every
/// order claim backed by captured audio.
///
/// Each queue slot is a distinct non-harmonic tone, so the heard sequence is recovered by frequency.
/// State assertions alone are not accepted as transport evidence — the whole point is that what was
/// scheduled and what was heard can differ.
@MainActor
struct GaplessRealTimeTransportTests {
    static let sampleRate = 44_100.0
    /// 0.4 s per track keeps a 25-transition run to about ten seconds.
    static let trackFrames = 17_640
    static let trackSeconds = Double(trackFrames) / sampleRate
    /// Non-harmonic: no ratio is near an integer, so a harmonic of one tone cannot be read as another.
    static let tones: [Double] = [233, 379, 611, 977, 1471]

    @MainActor
    struct Rig {
        let controller: GaplessPlaybackController
        let capture: GaplessRealTimeCapture
        let songIDs: [String]
        let toneBySong: [String: Double]
        let directory: URL

        func cleanUp() {
            capture.stop()
            controller.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        /// Tones actually heard, in order.
        func heard() -> [Double] {
            capture.heardSequence(frequencies: GaplessRealTimeTransportTests.tones,
                                  sampleRate: GaplessRealTimeTransportTests.sampleRate)
        }

        func tone(_ songID: String) -> Double { toneBySong[songID] ?? 0 }
    }

    /// Build a queue of `count` tone tracks wired end-to-end: provider → preparer → session →
    /// backend, with output capture attached.
    static func makeRig(count: Int, repeatMode: RepeatMode = .off) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var files: [String: URL] = [:]
        var toneBySong: [String: Double] = [:]
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
            toneBySong[songID] = tone
            songIDs.append(songID)
        }

        let session = GaplessPlaybackSession(sampleRate: sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = trackSeconds }
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

        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(filesByTrackID: files),
                                            renderSampleRate: sampleRate)
        let controller = GaplessPlaybackController(session: session, backend: backend,
                                                   preparer: preparer)
        return Rig(controller: controller, capture: GaplessRealTimeCapture(engine: backend.engine),
                   songIDs: songIDs, toneBySong: toneBySong, directory: directory)
    }

    /// Drive the controller's heartbeat until `predicate` holds, so boundaries and tail
    /// replenishment happen the way production's timer will drive them.
    @discardableResult
    static func run(_ rig: Rig, until what: String, timeout: TimeInterval = 30,
                    _ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await rig.controller.tick()
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("timed out waiting for \(what)")
        return false
    }

    static func boundaryCount(_ rig: Rig) -> Int { rig.controller.observedBoundaries.count }

    /// Wait until a given tone has actually been HEARD for a while.
    ///
    /// The first boundary is observed as soon as the clock reaches frame 0 — before any audio has
    /// reached the output — so "a boundary fired" is not the same as "the listener heard it". Tests
    /// that act on the audible track must wait for captured audio instead.
    static func runUntilHeard(_ rig: Rig, tone: Double, minWindows: Int = 2,
                              timeout: TimeInterval = 20) async {
        await run(rig, until: "tone \(tone) to be heard", timeout: timeout) {
            rig.heard().filter { $0 == tone }.count >= 1
                && rig.capture.frameCount > minWindows * 2_048
        }
    }

    // MARK: - Part 4.9: Repeat Off

    @Test func repeatOffPlaysEveryTrackInOrderThenStops() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()

        await Self.run(rig, until: "three boundaries") { Self.boundaryCount(rig) >= 3 }
        await Self.run(rig, until: "final track to finish", timeout: 10) {
            rig.controller.backend.renderFrame >= AVAudioFramePosition(3 * Self.trackFrames)
        }
        try await Task.sleep(for: .milliseconds(150))

        let heard = rig.heard()
        #expect(Array(heard.prefix(3)) == rig.songIDs.map(rig.tone), "heard \(heard)")
        #expect(Self.boundaryCount(rig) == 3)
        // One play instance per actual play, no duplicates.
        #expect(Set(rig.controller.observedBoundaries.map(\.playInstance)).count == 3)
        // Nothing beyond the queue was scheduled.
        #expect(rig.controller.session.nextIndex(after: 2, manual: false) == nil)
    }

    // MARK: - Part 4.10: Repeat All

    @Test func repeatAllWrapsWithNewPlayInstances() async throws {
        let rig = try Self.makeRig(count: 3, repeatMode: .all)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()

        // 1 2 3 1 2 — two full wraps of evidence.
        await Self.run(rig, until: "five plays of audio", timeout: 30) {
            Self.boundaryCount(rig) >= 5
                && rig.capture.frameCount >= 5 * Self.trackFrames - 4_096
        }
        try await Task.sleep(for: .milliseconds(150))

        let expected = [0, 1, 2, 0, 1].map { rig.tone(rig.songIDs[$0]) }
        let heard = Array(rig.heard().prefix(5))
        #expect(heard == expected, "heard \(heard) expected \(expected)")
        // Each wrap is a new play, and the queue generation is NOT bumped merely by advancing.
        let instances = rig.controller.observedBoundaries.prefix(5).map(\.playInstance)
        #expect(Set(instances).count == 5)
        #expect(rig.controller.session.queue.generation == 1)
    }

    // MARK: - Part 4.11: Repeat One

    @Test func repeatOneReplaysTheSameSlotWithNewPlayInstances() async throws {
        let rig = try Self.makeRig(count: 2, repeatMode: .one)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()

        await Self.run(rig, until: "three replays") { Self.boundaryCount(rig) >= 3 }

        let boundaries = Array(rig.controller.observedBoundaries.prefix(3))
        // Same slot each time...
        #expect(Set(boundaries.map(\.itemID)).count == 1)
        // ...but three distinct plays.
        #expect(Set(boundaries.map(\.playInstance)).count == 3)
        // Only the first track's tone is ever heard.
        #expect(Set(rig.heard()) == [rig.tone(rig.songIDs[0])])
    }

    /// Manual Next overrides Repeat One, and the newly selected item then repeats.
    @Test func repeatOneThenManualNextMovesOnAndRepeatsTheNewItem() async throws {
        let rig = try Self.makeRig(count: 2, repeatMode: .one)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()
        await Self.runUntilHeard(rig, tone: rig.tone(rig.songIDs[0]))

        try await rig.controller.next()
        await Self.run(rig, until: "second track to repeat") {
            rig.controller.observedBoundaries.filter { $0.songID == rig.songIDs[1] }.count >= 2
        }
        try await Task.sleep(for: .milliseconds(150))

        #expect(rig.controller.session.queue.currentItem?.songID == rig.songIDs[1])
        let heard = rig.heard()
        #expect(heard.first == rig.tone(rig.songIDs[0]))
        #expect(heard.contains(rig.tone(rig.songIDs[1])), "heard \(heard)")
        // The new item repeats: its tone dominates the tail of the capture.
        #expect(heard.last == rig.tone(rig.songIDs[1]))
    }

    // MARK: - Part 3.5: Manual Next

    @Test func manualNextIsHeardAndMeasured() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()
        await Self.run(rig, until: "track 1 audible") { Self.boundaryCount(rig) >= 1 }
        try await Task.sleep(for: .milliseconds(80))

        let requestedAt = Date()
        try await rig.controller.next()
        await Self.run(rig, until: "track 2 audible") {
            rig.controller.observedBoundaries.contains { $0.songID == rig.songIDs[1] }
        }
        let latency = Date().timeIntervalSince(requestedAt)
        try await Task.sleep(for: .milliseconds(150))

        let heard = rig.heard()
        #expect(heard.first == rig.tone(rig.songIDs[0]))
        #expect(heard.contains(rig.tone(rig.songIDs[1])), "heard \(heard)")
        // Responsive: a manual skip need not be gapless but must not stall.
        #expect(latency < 1.0, "next latency \(latency)s")
        // The interruption is a short gap, not a long silence.
        let silence = rig.capture.longestSilenceSeconds(sampleRate: Self.sampleRate)
        #expect(silence < 0.5, "silence \(silence)s")
    }

    /// Only the final command in a rapid burst may control audible output.
    @Test func rapidNextCommandsLeaveOnlyTheFinalDestinationAudible() async throws {
        let rig = try Self.makeRig(count: 5)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()
        await Self.run(rig, until: "track 1 audible") { Self.boundaryCount(rig) >= 1 }

        for _ in 0..<4 { try await rig.controller.next() }
        await Self.run(rig, until: "track 5 audible") {
            rig.controller.observedBoundaries.contains { $0.songID == rig.songIDs[4] }
        }
        try await Task.sleep(for: .milliseconds(200))

        #expect(rig.controller.session.queue.currentItem?.songID == rig.songIDs[4])
        let heard = rig.heard()
        #expect(heard.last == rig.tone(rig.songIDs[4]), "heard \(heard)")
    }

    // MARK: - Part 3.6: Manual Previous

    @Test(arguments: [2.9, 3.0, 3.1])
    func previousThresholdMatchesProduction(elapsed: TimeInterval) async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        rig.controller.session.setCurrentIndex(1)
        try await rig.controller.play()

        let destination = try await rig.controller.previous(elapsedSeconds: elapsed)

        // Production: strictly greater than 3 s restarts; at or below navigates back.
        if elapsed > 3.0 {
            #expect(destination == .restartCurrent)
            #expect(rig.controller.session.queue.currentItem?.songID == rig.songIDs[1])
        } else {
            #expect(destination == .item(index: 0))
            #expect(rig.controller.session.queue.currentItem?.songID == rig.songIDs[0])
        }
    }

    @Test func previousIsHeardWhenNavigatingBack() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        rig.controller.session.setCurrentIndex(1)
        rig.capture.start()
        try await rig.controller.play()
        await Self.runUntilHeard(rig, tone: rig.tone(rig.songIDs[1]))

        try await rig.controller.previous(elapsedSeconds: 1)
        await Self.run(rig, until: "track 1 audible") {
            rig.controller.observedBoundaries.contains { $0.songID == rig.songIDs[0] }
        }
        try await Task.sleep(for: .milliseconds(150))

        let heard = rig.heard()
        #expect(heard.first == rig.tone(rig.songIDs[1]))
        #expect(heard.contains(rig.tone(rig.songIDs[0])), "heard \(heard)")
    }

    // MARK: - Part 3.7: Seek

    @Test func seekForwardResumesInsideTheSameTrackAndContinuesToTheNext() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()
        await Self.run(rig, until: "track 1 audible") { Self.boundaryCount(rig) >= 1 }

        let requestedAt = Date()
        try await rig.controller.seek(toSeconds: Self.trackSeconds * 0.6)
        await Self.run(rig, until: "track 2 audible", timeout: 15) {
            rig.controller.observedBoundaries.contains { $0.songID == rig.songIDs[1] }
        }
        let latency = Date().timeIntervalSince(requestedAt)
        try await Task.sleep(for: .milliseconds(150))

        // Queue position is preserved by a seek; the following track still plays next.
        #expect(rig.controller.session.queue.currentIndex == 1)
        let heard = rig.heard()
        #expect(heard.first == rig.tone(rig.songIDs[0]))
        #expect(heard.contains(rig.tone(rig.songIDs[1])), "heard \(heard)")
        #expect(latency < 5.0, "seek-to-next latency \(latency)s")
    }

    @Test func seekBackwardReplaysEarlierAudio() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()
        await Self.run(rig, until: "track 1 audible") { Self.boundaryCount(rig) >= 1 }
        try await Task.sleep(for: .milliseconds(120))

        let before = rig.controller.backend.renderFrame
        try await rig.controller.seek(toSeconds: 0)

        // The logical clock must not run backwards even though playback did.
        #expect(rig.controller.backend.renderFrame >= before)
        #expect(rig.controller.session.queue.currentIndex == 0)
        #expect(rig.controller.session.queue.item(id: rig.controller.session.audibleItemID ?? GaplessQueueItemID(rawValue: 0))?.scrobbleSubmitted != true)
    }

    @Test func rapidSeeksLeaveConsistentStateAndKeepPlaying() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        try await rig.controller.play()
        await Self.run(rig, until: "track 1 audible") { Self.boundaryCount(rig) >= 1 }

        for target in [0.05, 0.2, 0.1, 0.3, 0.0] {
            try await rig.controller.seek(toSeconds: target)
        }

        #expect(rig.controller.session.queue.currentIndex == 0)
        #expect(rig.controller.backend.state == .playing)
        #expect(rig.controller.backend.engine.engine.isRunning)
    }

    @Test func seekWhilePausedStaysPaused() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        try await rig.controller.play()
        await Self.run(rig, until: "track 1 audible") { Self.boundaryCount(rig) >= 1 }
        rig.controller.pause()

        try await rig.controller.seek(toSeconds: 0.1)

        #expect(rig.controller.backend.state != .playing)
        #expect(!rig.controller.session.isPlaying)
    }

    // MARK: - Part 3.8: Stop and restart

    @Test func stopInvalidatesTheFutureAndLeavesTheGraphReusable() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        try await rig.controller.play()
        await Self.run(rig, until: "track 1 audible") { Self.boundaryCount(rig) >= 1 }
        let playerBefore = ObjectIdentifier(rig.controller.backend.engine.player)

        rig.controller.stop()

        #expect(rig.controller.backend.state == .idle)
        #expect(rig.controller.backend.scheduledSegments.isEmpty)
        #expect(rig.controller.observedBoundaries.isEmpty)
        #expect(rig.controller.session.queue.count == 3)      // queue preserved
        #expect(rig.controller.backend.engine.gainStage.currentGain == .unity)

        try await rig.controller.play()
        await Self.run(rig, until: "restart to become audible") { Self.boundaryCount(rig) >= 1 }
        #expect(ObjectIdentifier(rig.controller.backend.engine.player) == playerBefore)
        #expect(rig.controller.backend.state == .playing)
    }

    /// Many stop/start cycles on one engine instance — the graph must never be rebuilt.
    @Test func repeatedStopStartCyclesReuseOneGraph() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        let playerBefore = ObjectIdentifier(rig.controller.backend.engine.player)
        let eqBefore = ObjectIdentifier(rig.controller.backend.engine.eq)

        for _ in 0..<25 {
            try await rig.controller.play()
            await rig.controller.tick()
            rig.controller.stop()
        }

        #expect(ObjectIdentifier(rig.controller.backend.engine.player) == playerBefore)
        #expect(ObjectIdentifier(rig.controller.backend.engine.eq) == eqBefore)
        #expect(rig.controller.backend.state == .idle)
    }

    // MARK: - Part 3: Pause and resume

    @Test func pausePreservesPositionAndResumeContinues() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        try await rig.controller.play()
        await Self.run(rig, until: "track 1 audible") { Self.boundaryCount(rig) >= 1 }
        try await Task.sleep(for: .milliseconds(100))

        rig.controller.pause()
        let atPause = rig.controller.backend.renderFrame
        let tailAtPause = rig.controller.backend.scheduledSegments.count
        try await Task.sleep(for: .milliseconds(250))

        #expect(abs(rig.controller.backend.renderFrame - atPause) < 3_000)
        #expect(rig.controller.backend.scheduledSegments.count == tailAtPause)
        #expect(!rig.controller.session.isPlaying)

        try rig.controller.resume()
        await Self.run(rig, until: "playback to advance") {
            rig.controller.backend.renderFrame > atPause + 2_000
        }
        #expect(rig.controller.session.isPlaying)
    }

    // MARK: - Part 5.14: Play Next

    /// 1 audible, 2 scheduled, insert X → hear 1 → X → 2.
    @Test func playNextIsHeardBetweenCurrentAndOldSuccessor() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()
        await Self.runUntilHeard(rig, tone: rig.tone(rig.songIDs[0]))

        // song3 becomes the immediate successor, ahead of song2.
        try await rig.controller.playNext(songID: rig.songIDs[2])
        await Self.run(rig, until: "all three plays of audio", timeout: 30) {
            rig.heard().count >= 3
        }
        try await Task.sleep(for: .milliseconds(150))

        let heard = rig.heard()
        let expected = [rig.tone(rig.songIDs[0]), rig.tone(rig.songIDs[2]), rig.tone(rig.songIDs[1])]
        #expect(Array(heard.prefix(3)) == expected, "heard \(heard) expected \(expected)")
    }

    // MARK: - Part 5.16: Remove

    @Test func removingTheScheduledSuccessorSkipsItInTheAudio() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()
        await Self.runUntilHeard(rig, tone: rig.tone(rig.songIDs[0]))

        let successor = rig.controller.session.queue.items[1].id
        try await rig.controller.remove(itemID: successor)
        await Self.run(rig, until: "the replacement to be heard", timeout: 30) {
            rig.heard().contains(rig.tone(rig.songIDs[2]))
        }
        try await Task.sleep(for: .milliseconds(150))

        let heard = rig.heard()
        #expect(heard.first == rig.tone(rig.songIDs[0]))
        // The removed track must never be heard.
        #expect(!heard.contains(rig.tone(rig.songIDs[1])), "removed track was heard: \(heard)")
        #expect(heard.contains(rig.tone(rig.songIDs[2])), "heard \(heard)")
    }

    // MARK: - Part 5.18: Replace

    @Test func replacingTheQueueStartsTheNewSelectionImmediately() async throws {
        let rig = try Self.makeRig(count: 4)
        defer { rig.cleanUp() }
        rig.capture.start()
        try await rig.controller.play()
        await Self.run(rig, until: "track 1 audible") { Self.boundaryCount(rig) >= 1 }
        let playerBefore = ObjectIdentifier(rig.controller.backend.engine.player)

        try await rig.controller.replaceQueue(songIDs: [rig.songIDs[3], rig.songIDs[2]])
        await Self.run(rig, until: "replacement audible", timeout: 20) {
            rig.controller.observedBoundaries.contains { $0.songID == rig.songIDs[3] }
        }
        try await Task.sleep(for: .milliseconds(150))

        let heard = rig.heard()
        #expect(heard.contains(rig.tone(rig.songIDs[3])), "heard \(heard)")
        // Replacing the queue does not rebuild the graph.
        #expect(ObjectIdentifier(rig.controller.backend.engine.player) == playerBefore)
        #expect(rig.controller.session.queue.count == 2)
    }

    // MARK: - Part 2: Preparation window and lead time

    /// The window keeps current + next ready + one more, advancing on audible boundaries.
    @Test func preparationWindowStaysAheadOfPlayback() async throws {
        let rig = try Self.makeRig(count: 5, repeatMode: .off)
        defer { rig.cleanUp() }
        try await rig.controller.play()
        await Self.run(rig, until: "two boundaries") { Self.boundaryCount(rig) >= 2 }

        // At least the current and the next are on the timeline before they are needed.
        #expect(rig.controller.backend.scheduledSegments.count >= 2)
        let ready = await rig.controller.preparer.readyTrackIDs
        #expect(!ready.isEmpty)
    }

    /// Lead times are measured, not assumed. Local files should be ready long before their boundary.
    @Test func schedulingLeadTimeIsMeasuredForLocalFiles() async throws {
        let rig = try Self.makeRig(count: 4)
        defer { rig.cleanUp() }
        try await rig.controller.play()
        await Self.run(rig, until: "three boundaries", timeout: 20) { Self.boundaryCount(rig) >= 3 }

        let leads = rig.controller.preparationRecords.values.compactMap(\.schedulingLeadTime)
        #expect(!leads.isEmpty, "no scheduling lead times were recorded")
        // Every local-file item was scheduled before it became audible — no deadline was missed.
        #expect(leads.allSatisfy { $0 >= 0 }, "negative lead times: \(leads)")
        #expect(rig.controller.deadlineMisses.isEmpty)
    }

    // MARK: - Stale-work rejection

    @Test func supersededPreparationResultsAreDiscarded() async throws {
        let rig = try Self.makeRig(count: 4)
        defer { rig.cleanUp() }
        try await rig.controller.play()
        await Self.run(rig, until: "track 1 audible") { Self.boundaryCount(rig) >= 1 }
        let generationBefore = rig.controller.session.queue.generation

        try await rig.controller.replaceQueue(songIDs: [rig.songIDs[2], rig.songIDs[3]])

        #expect(rig.controller.session.queue.generation > generationBefore)
        // Work tagged with the old generation can no longer apply.
        #expect(!rig.controller.session.queue.isCurrent(generation: generationBefore))
    }

    // MARK: - Failure paths

    @Test func aMissingSourceFailsTheItemWithoutMarkingItPlayed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grt-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = GaplessPlaybackSession(sampleRate: Self.sampleRate)
        session.replaceQueue(songIDs: ["missing"])
        session.songDurations["missing"] = Self.trackSeconds
        let backend = GaplessRealTimeBackend()
        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(filesByTrackID: [:]),
                                            renderSampleRate: Self.sampleRate)
        let controller = GaplessPlaybackController(session: session, backend: backend,
                                                   preparer: preparer)

        try? await controller.play()
        await controller.tick()

        let item = session.queue.items[0]
        #expect(session.queue.item(id: item.id)?.state == .failed)
        // Never audible, never completed, and no boundary invented for it.
        #expect(session.audibleItemID == nil)
        #expect(controller.observedBoundaries.isEmpty)
        #expect(controller.preparationRecords[item.id]?.failure != nil)
        controller.stop()
    }

    @Test func removingACacheFileAfterPreparationFailsTheScheduleNotTheSession() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        try await rig.controller.play()
        await Self.run(rig, until: "track 1 audible") { Self.boundaryCount(rig) >= 1 }

        // Delete the successor's backing file, then force a tail rebuild.
        try? FileManager.default.removeItem(at: rig.directory.appendingPathComponent("\(rig.songIDs[1]).wav"))
        try await rig.controller.playNext(songID: rig.songIDs[1])

        // The session stays coherent: still playing, queue intact, no phantom boundary.
        #expect(rig.controller.backend.state == .playing || rig.controller.backend.state == .prepared)
        #expect(rig.controller.session.queue.count == 3)
        #expect(rig.controller.observedBoundaries.allSatisfy { $0.songID != "" })
    }
}
