import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Tail replacement, proven against **captured real-time audio** rather than internal state.
///
/// This mechanism underlies Next, Previous, seek, Play Next, reorder and queue replacement, so it is
/// proven on its own first. Each track is a different tone, the engine's output is recorded, and the
/// heard sequence is recovered by frequency — so "1 → X → Y" is a statement about what came out of
/// the mixer, not about the order things were scheduled in.
@MainActor
struct GaplessTailReplacementTests {
    static let sampleRate = 44_100.0
    /// 0.4 s per part: long enough to identify by frequency, short enough for fast tests.
    static let partFrames = 17_640
    static let partSeconds = Double(partFrames) / sampleRate

    /// Deliberately NON-harmonic tones.
    ///
    /// An earlier version used 220/330/440/550/660 and the analysis reported 440 Hz playing when
    /// only 220 Hz had — because 440 is the second harmonic of 220, and a pure tone carries enough
    /// harmonic energy through the mixer to win a naive "which candidate has most energy"
    /// comparison. No ratio between these is near an integer, so one tone's harmonic can never be
    /// mistaken for another tone.
    static let tones: [Double] = [233, 379, 611, 977, 1471]

    static func makeTonePart(frequency: Double, frames: Int = partFrames) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gtail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("tone\(Int(frequency)).wav")
        var samples = [Int16](repeating: 0, count: frames)
        for i in 0..<frames {
            let value = 0.5 * sin(2.0 * .pi * frequency * Double(i) / sampleRate)
            samples[i] = Int16((max(-1, min(1, value)) * 32767).rounded())
        }
        try GaplessPipelineOfflineTests.writeWav(url: url, samples: samples, sampleRate: sampleRate)
        return url
    }

    struct Fixture {
        let urls: [URL]
        let tracks: [GaplessPreparedTrack]
        let frequencies: [Double]
        func cleanUp() {
            for url in urls { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        }
    }

    static func makeFixture(_ frequencies: [Double]) throws -> Fixture {
        let urls = try frequencies.map { try makeTonePart(frequency: $0) }
        let tracks = try urls.map {
            try GaplessTrackPreparer.describe(trackID: $0.lastPathComponent, fileURL: $0,
                                              renderSampleRate: sampleRate)
        }
        return Fixture(urls: urls, tracks: tracks, frequencies: frequencies)
    }

    static func entry(_ track: GaplessPreparedTrack, slot: UInt64, generation: UInt64 = 1)
        -> (track: GaplessPreparedTrack, itemID: GaplessQueueItemID, generation: UInt64) {
        (track, GaplessQueueItemID(rawValue: slot), generation)
    }

    static func makeBackend() -> GaplessRealTimeBackend {
        let backend = GaplessRealTimeBackend()
        #if os(iOS)
        backend.activateAudioSession = {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        }
        backend.deactivateAudioSession = { try? AVAudioSession.sharedInstance().setActive(false) }
        #endif
        return backend
    }

    @discardableResult
    static func waitUntil(_ what: String, timeout: TimeInterval = 15,
                          _ predicate: @MainActor () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("timed out waiting for \(what)")
        return false
    }

    // MARK: - Semantics

    /// `AVAudioPlayerNode` offers no per-buffer cancellation: `stop()` discards *every* pending
    /// schedule. This pins that, so the design is not built on a capability that does not exist.
    @Test func playerNodeHasNoSurgicalBufferCancellation() async throws {
        let fixture = try Self.makeFixture([233, 379, 611])
        defer { fixture.cleanUp() }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        try await backend.scheduleForTesting(fixture.tracks.enumerated().map { Self.entry($1, slot: UInt64($0 + 1)) })
        #expect(backend.scheduledSegments.count == 3)

        try await backend.start()
        defer { backend.stop() }
        await Self.waitUntil("playback to begin") { backend.renderFrame > 2_000 }

        // The only available mechanism drops everything after the audible position.
        let resume = await backend.resetTail()
        #expect(backend.scheduledSegments.allSatisfy { $0.startFrame <= resume })
    }

    /// Each replacement gets its own tail identity, distinct from queue generation and slot ID.
    @Test func eachReplacementBumpsTheTailGeneration() async throws {
        let fixture = try Self.makeFixture([233, 379])
        defer { fixture.cleanUp() }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        try await backend.scheduleForTesting([Self.entry(fixture.tracks[0], slot: 1)])
        let first = backend.tailGeneration
        try await backend.start()
        defer { backend.stop() }
        await Self.waitUntil("playback") { backend.renderFrame > 1_000 }

        await backend.resetTail()
        let second = backend.tailGeneration
        await backend.resetTail()
        let third = backend.tailGeneration

        #expect(second > first)
        #expect(third > second)
        #expect(backend.isCurrentTail(third))
        #expect(!backend.isCurrentTail(first))
        #expect(!backend.isCurrentTail(second))
    }

    // MARK: - Controlled replacement, verified by captured audio

    /// 1 audible, 2 and 3 scheduled → replace tail with X, Y → hear 1 → X → Y.
    @Test func replacingTheFutureTailChangesWhatIsHeard() async throws {
        let fixture = try Self.makeFixture([233, 379, 611, 977, 1471])
        defer { fixture.cleanUp() }
        let backend = Self.makeBackend()
        let capture = GaplessRealTimeCapture(engine: backend.engine)
        try backend.prepareGraph()
        // 1 (233 Hz), 2 (379 Hz), 3 (611 Hz)
        try await backend.scheduleForTesting([Self.entry(fixture.tracks[0], slot: 1),
                                              Self.entry(fixture.tracks[1], slot: 2),
                                              Self.entry(fixture.tracks[2], slot: 3)])
        try await backend.start()
        capture.start()
        defer { capture.stop(); backend.stop() }

        // Replace early in track 1, well before its boundary.
        await Self.waitUntil("track 1 to be established") { backend.renderFrame > 4_000 }
        await backend.resetTail()
        // X (977 Hz), Y (1471 Hz)
        try await backend.scheduleForTesting([Self.entry(fixture.tracks[3], slot: 4, generation: 2),
                                              Self.entry(fixture.tracks[4], slot: 5, generation: 2)])

        await Self.waitUntil("the replacement tail to finish", timeout: 20) {
            await backend.observeBoundaries()
            return backend.renderFrame >= AVAudioFramePosition(3 * Self.partFrames)
        }
        try await Task.sleep(for: .milliseconds(200))

        let heard = capture.heardSequence(frequencies: Self.tones, sampleRate: Self.sampleRate)
        #expect(heard.first == 233, "expected track 1 first, heard \(heard)")
        // The discarded tracks must not appear anywhere in the output.
        #expect(!heard.contains(379), "stale successor was heard: \(heard)")
        #expect(!heard.contains(611), "stale third track was heard: \(heard)")
        #expect(heard.contains(977), "replacement X was not heard: \(heard)")
    }

    /// Repeated replacements: only the last one may be heard.
    @Test func onlyTheFinalReplacementBecomesAudible() async throws {
        let fixture = try Self.makeFixture([233, 379, 611, 977])
        defer { fixture.cleanUp() }
        let backend = Self.makeBackend()
        let capture = GaplessRealTimeCapture(engine: backend.engine)
        try backend.prepareGraph()
        try await backend.scheduleForTesting([Self.entry(fixture.tracks[0], slot: 1)])
        try await backend.start()
        capture.start()
        defer { capture.stop(); backend.stop() }
        await Self.waitUntil("track 1") { backend.renderFrame > 4_000 }

        // Tail A → B → C → D in quick succession; only D should ever be heard.
        for (index, track) in [fixture.tracks[1], fixture.tracks[2], fixture.tracks[3]].enumerated() {
            await backend.resetTail()
            try await backend.scheduleForTesting([Self.entry(track, slot: UInt64(index + 2),
                                                             generation: UInt64(index + 2))])
        }

        await Self.waitUntil("final tail to render", timeout: 20) {
            await backend.observeBoundaries()
            return backend.renderFrame >= AVAudioFramePosition(2 * Self.partFrames)
        }
        try await Task.sleep(for: .milliseconds(200))

        let heard = capture.heardSequence(frequencies: Self.tones, sampleRate: Self.sampleRate)
        #expect(heard.contains(233))
        #expect(heard.contains(977), "final replacement was not heard: \(heard)")
        // The two superseded tails must be inaudible.
        #expect(!heard.contains(379), "superseded tail B was heard: \(heard)")
        #expect(!heard.contains(611), "superseded tail C was heard: \(heard)")
    }

    /// A superseded tail must not emit boundary events.
    @Test func supersededTailEmitsNoBoundaryEvents() async throws {
        let fixture = try Self.makeFixture([233, 379, 611])
        defer { fixture.cleanUp() }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        try await backend.scheduleForTesting([Self.entry(fixture.tracks[0], slot: 1),
                                              Self.entry(fixture.tracks[1], slot: 2)])
        try await backend.start()
        defer { backend.stop() }
        await Self.waitUntil("track 1") { backend.renderFrame > 4_000 }
        await backend.observeBoundaries()
        let discardedInstances = Set(backend.scheduledSegments.map(\.playInstance))

        await backend.resetTail()
        try await backend.scheduleForTesting([Self.entry(fixture.tracks[2], slot: 3, generation: 2)])
        let survivingTail = backend.tailGeneration

        await Self.waitUntil("replacement to render", timeout: 20) {
            await backend.observeBoundaries()
            return backend.renderFrame >= AVAudioFramePosition(2 * Self.partFrames)
        }
        let events = backend.drainBoundaryEvents()

        // Every event belongs to a live tail, and none to a play instance that was discarded
        // before ever becoming audible.
        for event in events {
            #expect(event.tailGeneration <= survivingTail)
            if event.tailGeneration != survivingTail {
                // Only the still-audible original segment may predate the replacement.
                #expect(discardedInstances.contains(event.playInstance))
                #expect(event.scheduledStartFrame == 0)
            }
        }
        #expect(Set(events.map(\.playInstance)).count == events.count, "duplicate boundary events")
    }

    // MARK: - Replacement lead time

    /// How close to a boundary can a replacement still take effect?
    ///
    /// Reports the measured outcome per lead time instead of assuming a threshold. What limits this
    /// is the audio already handed to the hardware: once frames are in the output buffer they will
    /// play regardless of what the node does next, so there is an unavoidable region whose size is a
    /// property of the host's buffer, not of this code.
    @Test func replacementLeadTimeIsMeasuredNotAssumed() async throws {
        let leadTimes: [TimeInterval] = [0.25, 0.1, 0.05]
        var outcomes: [(lead: TimeInterval, replaced: Bool)] = []

        for lead in leadTimes {
            let fixture = try Self.makeFixture([233, 379, 977])
            defer { fixture.cleanUp() }
            let backend = Self.makeBackend()
            let capture = GaplessRealTimeCapture(engine: backend.engine)
            try backend.prepareGraph()
            try await backend.scheduleForTesting([Self.entry(fixture.tracks[0], slot: 1),
                                                  Self.entry(fixture.tracks[1], slot: 2)])
            try await backend.start()
            capture.start()

            // Wait until `lead` seconds before track 1's boundary.
            let target = AVAudioFramePosition(Double(Self.partFrames) - lead * Self.sampleRate)
            await Self.waitUntil("lead point \(lead)s") { backend.renderFrame >= target }
            await backend.resetTail()
            try await backend.scheduleForTesting([Self.entry(fixture.tracks[2], slot: 3, generation: 2)])

            await Self.waitUntil("replacement window", timeout: 20) {
                backend.renderFrame >= AVAudioFramePosition(2 * Self.partFrames)
            }
            try await Task.sleep(for: .milliseconds(150))
            let heard = capture.heardSequence(frequencies: Self.tones, sampleRate: Self.sampleRate)
            capture.stop(); backend.stop()
            // The next iteration starts a fresh engine over the same audio session; let this
            // backend's ordered teardown finish so the two cannot interleave.
            await backend.settleTransport()

            // "Replaced" means the old successor never became audible.
            outcomes.append((lead, !heard.contains(379)))
        }

        // Report every outcome so the boundary is visible in the record, then assert the one that
        // matters for transport: a quarter of a second of lead is enough.
        let summary = outcomes.map { "\(Int($0.lead * 1000))ms→\($0.replaced ? "replaced" : "old successor heard")" }
        #expect(outcomes.first(where: { $0.lead == 0.25 })?.replaced == true,
                "250 ms lead failed to replace; outcomes: \(summary)")
    }

    // MARK: - Clock and graph integrity

    @Test func clockStaysMonotonicAcrossManyReplacements() async throws {
        let fixture = try Self.makeFixture([233, 379])
        defer { fixture.cleanUp() }
        let backend = Self.makeBackend()
        try backend.prepareGraph()
        try await backend.scheduleForTesting([Self.entry(fixture.tracks[0], slot: 1)])
        try await backend.start()
        defer { backend.stop() }
        await Self.waitUntil("playback") { backend.renderFrame > 2_000 }

        let playerBefore = ObjectIdentifier(backend.engine.player)
        let eqBefore = ObjectIdentifier(backend.engine.eq)
        var previous: AVAudioFramePosition = 0
        for index in 0..<10 {
            await backend.resetTail()
            try await backend.scheduleForTesting([Self.entry(fixture.tracks[1], slot: 2,
                                                             generation: UInt64(index + 2))])
            let now = backend.renderFrame
            #expect(now >= previous, "clock went backwards: \(now) after \(previous)")
            previous = now
            try await Task.sleep(for: .milliseconds(20))
        }

        // Ten replacements, no engine reconstruction.
        #expect(ObjectIdentifier(backend.engine.player) == playerBefore)
        #expect(ObjectIdentifier(backend.engine.eq) == eqBefore)
        #expect(backend.engine.engine.isRunning)
        #expect(backend.state == .playing)
    }
}
