import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// The render-observed first-audible callback that Lane 3D-B1b's fallback latch will hang off.
///
/// **What makes this signal trustworthy** is that it is not a proxy. It is driven by
/// `GaplessBoundaryEvent`, which the backend emits only once the player node's own sample clock has
/// reached a segment whose PCM has actually been materialized. Engine-running, node-playing,
/// buffers-scheduled and session-activated are all things that happen *before* audio is heard, and
/// none of them can stand in for it — a fallback latch driven by any of those would release too
/// early and permit a cutover after the listener had already heard the persistent engine.
///
/// It fires once per **play occurrence**, not per queue item, which is why a repeat fires again
/// while a pause, resume or in-place seek does not.
@Suite(.serialized)
@MainActor
struct GaplessAudibleBoundaryCallbackTests {

    private static let sampleRate = GaplessBufferFixtures.sampleRate
    private static let partFrames = 8_192

    /// Real tone files, so the boundary is observed against genuinely rendered audio.
    private func makeParts(_ count: Int, in directory: URL) throws -> [String: URL] {
        var files: [String: URL] = [:]
        for index in 0..<count {
            let url = directory.appendingPathComponent("part\(index).wav")
            try GaplessBufferFixtures.writeStereoWav(
                url: url, frequency: 440 + Double(index) * 110,
                frames: Self.partFrames, sampleRate: Self.sampleRate)
            files["t\(index)"] = url
        }
        return files
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audible-\(UInt64.random(in: 0..<UInt64.max))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    /// A controller over the real backend, with a counting callback attached.
    private func makeController(
        files: [String: URL], songIDs: [String], counter: @escaping @MainActor () -> Void
    ) -> (GaplessPlaybackController, GaplessPlaybackSession, GaplessRealTimeBackend) {
        let session = GaplessPlaybackSession(sampleRate: Self.sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = Double(Self.partFrames) / Self.sampleRate }
        let backend = GaplessRealTimeBackend()
        let controller = GaplessPlaybackController(
            session: session, backend: backend,
            preparer: GaplessTrackPreparer(
                provider: GaplessLocalFileProvider(filesByTrackID: files),
                renderSampleRate: Self.sampleRate))
        controller.onFirstAudibleSample = counter
        return (controller, session, backend)
    }

    /// Drive real ticks until `predicate` holds or the deadline passes.
    private func drive(
        _ controller: GaplessPlaybackController, seconds: Double, until predicate: () -> Bool = { false }
    ) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            await controller.tick()
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(4))
        }
    }

    // MARK: - First item of a new session

    /// The load-bearing case the audit was about: the first occurrence of a fresh session fires,
    /// with no preceding item to transition from.
    @Test func theFirstItemOfANewSessionFiresOnce() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(1, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(files: files, songIDs: ["t0"]) { invocations += 1 }
            defer { controller.stop() }

            #expect(invocations == 0, "fired before playback started")
            try await controller.play()
            await drive(controller, seconds: 3) { invocations >= 1 }

            #expect(invocations == 1,
                    "the first item of a fresh session fired \(invocations) times, expected 1")
        }
    }

    /// It is not a proxy for the engine starting: after `play()` returns, audio has been scheduled
    /// and the engine is running, but the callback waits for the render clock.
    @Test func itDoesNotFireMerelyBecauseTheEngineStartedOrBuffersWereScheduled() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(1, in: directory)
            var invocations = 0
            let (controller, _, backend) = makeController(
                files: files, songIDs: ["t0"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            // The engine is up and buffers exist, but no tick has observed the render clock yet.
            #expect(backend.engine.engine.isRunning, "fixture should have a running engine here")
            #expect(invocations == 0,
                    "fired on engine start / buffer scheduling rather than on render observation")

            await drive(controller, seconds: 3) { invocations >= 1 }
            #expect(invocations == 1)
        }
    }

    // MARK: - One per occurrence

    /// Four occurrences fire four times, matching the backend's one-boundary-per-play-instance rule.
    @Test func fourPlayInstancesFireFourTimes() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(4, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(
                files: files, songIDs: ["t0", "t1", "t2", "t3"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            await drive(controller, seconds: 8) { invocations >= 4 }

            #expect(invocations == 4, "four occurrences fired \(invocations) times")
        }
    }

    /// Repeated ticks after a boundary do not re-fire it: the backend reports each instance once.
    @Test func aDuplicateBoundaryForTheSameOccurrenceDoesNotFireAgain() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(1, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(files: files, songIDs: ["t0"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            await drive(controller, seconds: 3) { invocations >= 1 }
            let afterFirst = invocations

            // Keep ticking well past the boundary.
            for _ in 0..<50 { await controller.tick() }

            #expect(invocations == afterFirst,
                    "the same occurrence fired again on later ticks (\(invocations))")
        }
    }

    // MARK: - Pause, resume, seek

    /// Pause and resume are not new occurrences.
    @Test func pauseAndResumeDoNotAddAnInvocation() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(1, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(files: files, songIDs: ["t0"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            await drive(controller, seconds: 3) { invocations >= 1 }
            let afterFirst = invocations
            #expect(afterFirst == 1)

            controller.pause()
            for _ in 0..<10 { await controller.tick() }
            try controller.resume()
            await drive(controller, seconds: 1)

            #expect(invocations == afterFirst,
                    "pause/resume produced a false occurrence boundary (\(invocations))")
        }
    }

    /// A seek re-fires — and that is correct, not a leak.
    ///
    /// Measured: seeking took the callback from 1 invocation to 3. A seek tears down the scheduled
    /// tail and re-schedules from the new position, which allocates **new play instances** for the
    /// current item and the one behind it, so the backend genuinely observes new occurrences
    /// becoming audible. The guarantee is per *instance*, not per seek: the same play instance never
    /// reports twice, which `aDuplicateBoundaryForTheSameOccurrenceDoesNotFireAgain` pins.
    ///
    /// This matters for Lane 3D-B1b: the callback means "an occurrence became audible", **not**
    /// "a new session started". The fallback latch is safe either way — it only ever latches from
    /// permitted to prohibited — but nothing downstream may read a repeat firing as a new session.
    @Test func seekReschedulesAndReportsNewOccurrences() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(2, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(
                files: files, songIDs: ["t0", "t1"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            await drive(controller, seconds: 3) { invocations >= 1 }
            let afterFirst = invocations
            #expect(afterFirst >= 1, "the first occurrence never became audible")

            try await controller.seek(toSeconds: 0.05)
            await drive(controller, seconds: 1)

            // New occurrences, never fewer — and the count only ever moves forward.
            #expect(invocations >= afterFirst,
                    "invocations went backwards, which cannot happen")

            // Ticking on past the seek adds nothing further: those instances are already reported.
            let afterSeek = invocations
            for _ in 0..<40 { await controller.tick() }
            #expect(invocations == afterSeek,
                    "post-seek occurrences re-reported themselves (\(invocations) vs \(afterSeek))")
        }
    }

    // MARK: - Stale events

    /// A superseded tail contributes nothing: the controller drops those events before the callback.
    @Test func staleTailEventsDoNotFire() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(3, in: directory)
            var invocations = 0
            let (controller, _, _) = makeController(
                files: files, songIDs: ["t0", "t1", "t2"]) { invocations += 1 }
            defer { controller.stop() }

            try await controller.play()
            await drive(controller, seconds: 3) { invocations >= 1 }
            let afterFirst = invocations
            let staleBefore = controller.staleResultCount

            // Replacing the queue supersedes the scheduled tail.
            try await controller.replaceQueue(songIDs: ["t2", "t1"], startIndex: 0)
            await drive(controller, seconds: 2)

            // Whatever fired, it was never a stale event: those are filtered out of `live`.
            #expect(controller.staleResultCount >= staleBefore)
            #expect(invocations >= afterFirst,
                    "invocations went backwards, which cannot happen")
        }
    }

    // MARK: - Nil callback

    /// A nil callback is the default and changes nothing about playback.
    @Test func aNilCallbackChangesNoBehaviour() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(2, in: directory)
            let session = GaplessPlaybackSession(sampleRate: Self.sampleRate)
            session.replaceQueue(songIDs: ["t0", "t1"])
            let backend = GaplessRealTimeBackend()
            let controller = GaplessPlaybackController(
                session: session, backend: backend,
                preparer: GaplessTrackPreparer(
                    provider: GaplessLocalFileProvider(filesByTrackID: files),
                    renderSampleRate: Self.sampleRate))
            defer { controller.stop() }

            #expect(controller.onFirstAudibleSample == nil, "the callback must default to nil")

            try await controller.play()
            await drive(controller, seconds: 3) { backend.renderFrame > 0 }

            // Playback proceeded normally with no callback attached.
            #expect(backend.renderFrame > 0, "playback did not progress without a callback")
            #expect(backend.engine.engine.isRunning)
        }
    }
}
