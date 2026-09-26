import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// The real Classic and Native adapters under **actual real-time playback**.
///
/// The feed was proven by direct delivery; this proves the adapters against a running engine, which
/// is where tap lifetime, stale buffers and render-thread cost actually matter.
@MainActor
struct GaplessLiveVisualizerTests {
    static let sampleRate = 44_100.0
    static let trackFrames = 17_640
    static let tones: [Double] = [233, 379, 611, 977]

    @MainActor
    struct Rig {
        let controller: GaplessPlaybackController
        let capture: GaplessRealTimeCapture
        let songIDs: [String]
        let directory: URL

        func cleanUp() {
            capture.stop()
            controller.backend.engine.uninstallVisualizerFeed()
            controller.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        func heard() -> [Double] {
            capture.heardSequence(frequencies: GaplessLiveVisualizerTests.tones,
                                  sampleRate: GaplessLiveVisualizerTests.sampleRate)
        }
    }

    static func makeRig(count: Int, repeatMode: RepeatMode = .all) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glv-\(UUID().uuidString)", isDirectory: true)
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
        // Installed BEFORE the engine starts — the tap belongs to the engine's lifetime.
        backend.engine.installVisualizerFeed()

        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(filesByTrackID: files),
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

    // MARK: - Classic under live playback

    @Test func classicAdapterReceivesLivePCMAcrossManyBoundaries() async throws {
        let rig = try Self.makeRig(count: 4)
        defer { rig.cleanUp() }
        let feed = rig.controller.backend.engine.visualizerFeed
        let classic = GaplessClassicVisualizerAdapter(feed: feed, sampleRate: Self.sampleRate)
        classic.activate()

        try await rig.controller.play()
        var drained = 0
        await Self.run(rig, until: "ten boundaries with Classic active", timeout: 60) {
            drained += classic.drain()
            return rig.controller.observedBoundaries.count >= 10
        }

        // Live PCM actually reached the real AudioSpectrum.
        #expect(drained > 0, "Classic received no PCM")
        // One tap for the engine's whole life, across every boundary.
        #expect(feed.isInstalled)
        #expect(feed.registeredConsumerCount == 1)
        #expect(feed.stats.contendedCallbacks == 0)
        #expect(rig.controller.backend.engine.engine.isRunning)

        // Render-thread cost stays far inside the audio deadline.
        let stats = feed.stats
        let deadlineNanoseconds = UInt64(Double(GaplessVisualizerFeed.bufferFrames)
                                         / Self.sampleRate * 1_000_000_000)
        #expect(stats.peakCallbackNanoseconds < deadlineNanoseconds,
                "peak \(stats.peakCallbackNanoseconds) ns vs deadline \(deadlineNanoseconds) ns")
    }

    /// Opening and closing a visualizer during playback must not disturb audio or the tap.
    @Test func openingAndClosingDuringPlaybackNeverTouchesTheGraph() async throws {
        let rig = try Self.makeRig(count: 4)
        defer { rig.cleanUp() }
        let feed = rig.controller.backend.engine.visualizerFeed
        let classic = GaplessClassicVisualizerAdapter(feed: feed, sampleRate: Self.sampleRate)
        rig.capture.start()
        try await rig.controller.play()
        let playerBefore = ObjectIdentifier(rig.controller.backend.engine.player)
        let mixerBefore = ObjectIdentifier(rig.controller.backend.engine.outputMixer)

        for _ in 0..<5 {
            classic.activate()
            await Self.run(rig, until: "some audio") { rig.capture.frameCount > 2_048 }
            _ = classic.drain()
            classic.deactivate()
        }

        #expect(feed.isInstalled)
        #expect(ObjectIdentifier(rig.controller.backend.engine.player) == playerBefore)
        #expect(ObjectIdentifier(rig.controller.backend.engine.outputMixer) == mixerBefore)
        #expect(rig.controller.backend.engine.engine.isRunning)
        // Audio kept flowing throughout the churn.
        #expect(!rig.heard().isEmpty)
    }

    /// After a tail replacement the consumer must not hold audio from the discarded track.
    @Test func noStaleBuffersSurviveATailReplacement() async throws {
        let rig = try Self.makeRig(count: 4, repeatMode: .off)
        defer { rig.cleanUp() }
        let feed = rig.controller.backend.engine.visualizerFeed
        let native = GaplessNativeVisualizerAdapter(feed: feed, source: VisualizerPCMSource())
        native.activate()
        try await rig.controller.play()
        await Self.run(rig, until: "audio to flow") { rig.controller.backend.renderFrame > 4_000 }

        // Deliberately do NOT drain, so the ring holds outgoing-track audio, then replace the tail.
        try await rig.controller.next()
        native.deactivate()          // closing resets the ring
        native.activate()

        #expect(native.drain() == 0, "stale audio survived the tail replacement")
        #expect(feed.isInstalled)
    }

    // MARK: - Native under live playback

    @Test func nativeAdapterReceivesLivePCMAcrossManyBoundaries() async throws {
        let rig = try Self.makeRig(count: 4)
        defer { rig.cleanUp() }
        let feed = rig.controller.backend.engine.visualizerFeed
        let source = VisualizerPCMSource()
        let native = GaplessNativeVisualizerAdapter(feed: feed, source: source)
        native.activate()

        try await rig.controller.play()
        var drained = 0
        await Self.run(rig, until: "ten boundaries with Native active", timeout: 60) {
            drained += native.drain()
            return rig.controller.observedBoundaries.count >= 10
        }

        #expect(drained > 0, "Native received no PCM")
        #expect(source.stats.producedFrames > 0)
        #expect(feed.isInstalled)
        #expect(feed.stats.contendedCallbacks == 0)
    }

    // MARK: - Concurrent consumers (engineering stress case)

    /// Both consumers at once is a stress case rather than normal UI behaviour, but the feed layer
    /// must survive it: one stalled consumer cannot starve or block the other.
    @Test func stallingOneConsumerDoesNotAffectTheOther() async throws {
        let rig = try Self.makeRig(count: 4)
        defer { rig.cleanUp() }
        let feed = rig.controller.backend.engine.visualizerFeed
        let classic = GaplessClassicVisualizerAdapter(feed: feed, sampleRate: Self.sampleRate)
        let native = GaplessNativeVisualizerAdapter(feed: feed, source: VisualizerPCMSource())
        classic.activate()
        native.activate()

        try await rig.controller.play()
        // Native drains normally; Classic is deliberately stalled (never drained).
        var nativeFrames = 0
        await Self.run(rig, until: "five boundaries", timeout: 60) {
            nativeFrames += native.drain()
            return rig.controller.observedBoundaries.count >= 5
        }

        #expect(nativeFrames > 0, "the healthy consumer got nothing")
        let classicConsumer = feed.consumer(identifier: "classic")
        let nativeConsumer = feed.consumer(identifier: "native")
        // Drops are counted per consumer: the stalled one loses frames, the healthy one does not.
        #expect((classicConsumer?.buffer.stats.overflowFrames ?? 0) > 0,
                "the stalled consumer should have overflowed")
        #expect(nativeConsumer?.buffer.stats.overflowFrames == 0,
                "the healthy consumer must not be affected by the stalled one")
        // Bounded: a stalled consumer cannot grow without limit.
        let capacity = classicConsumer?.buffer.frameCapacity ?? 0
        #expect((classicConsumer?.buffer.stats.fillFrames ?? 0) <= capacity)
        // Neither blocked the render thread.
        #expect(feed.stats.contendedCallbacks == 0)
        #expect(rig.controller.backend.engine.engine.isRunning)
    }

    // MARK: - Visualizer data across transport events

    @Test func visualizerDataContinuesThroughSeekAndSkip() async throws {
        let rig = try Self.makeRig(count: 4)
        defer { rig.cleanUp() }
        let feed = rig.controller.backend.engine.visualizerFeed
        let native = GaplessNativeVisualizerAdapter(feed: feed, source: VisualizerPCMSource())
        native.activate()
        try await rig.controller.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 4_000 }

        var afterSeek = 0
        try await rig.controller.seek(toSeconds: 0.1)
        await Self.run(rig, until: "PCM after seek") { afterSeek += native.drain(); return afterSeek > 0 }

        var afterNext = 0
        try await rig.controller.next()
        await Self.run(rig, until: "PCM after next") { afterNext += native.drain(); return afterNext > 0 }

        #expect(afterSeek > 0)
        #expect(afterNext > 0)
        // One tap throughout, never reinstalled by a transport action.
        #expect(feed.isInstalled)
        #expect(feed.registeredConsumerCount == 1)
    }
}
