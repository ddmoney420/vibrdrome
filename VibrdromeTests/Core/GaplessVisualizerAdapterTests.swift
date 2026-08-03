import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// The real Classic and Native visualizers, driven from the shared persistent feed.
///
/// The property under test is that a visualizer is a *consumer* of audio and never a participant in
/// the audio path: opening, closing, and switching must leave the tap installed exactly once and the
/// graph untouched.
@MainActor
struct GaplessVisualizerAdapterTests {
    static let sampleRate = 44_100.0

    static func makeBuffer(frames: Int, amplitude: Float = 0.4) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<2 {
            for i in 0..<frames {
                buffer.floatChannelData![channel][i] =
                    amplitude * Float(sin(2.0 * .pi * 220.0 * Double(i) / sampleRate))
            }
        }
        return buffer
    }

    // MARK: - Classic

    @Test func classicAdapterReceivesAudioOnlyWhileActive() {
        let feed = GaplessVisualizerFeed()
        let adapter = GaplessClassicVisualizerAdapter(feed: feed, sampleRate: Self.sampleRate)

        // Closed: the feed still runs, the adapter does no downstream work.
        feed.deliver(Self.makeBuffer(frames: 1_024))
        #expect(adapter.drain() == 0)

        adapter.activate()
        feed.deliver(Self.makeBuffer(frames: 1_024))
        #expect(adapter.drain() == 1_024)

        adapter.deactivate()
        feed.deliver(Self.makeBuffer(frames: 1_024))
        #expect(adapter.drain() == 0)
    }

    /// Closing must not leave audio from minutes ago waiting for the next open.
    @Test func classicAdapterDiscardsBufferedAudioOnClose() {
        let feed = GaplessVisualizerFeed()
        let adapter = GaplessClassicVisualizerAdapter(feed: feed, sampleRate: Self.sampleRate)
        adapter.activate()
        feed.deliver(Self.makeBuffer(frames: 2_048))

        adapter.deactivate()
        adapter.activate()

        #expect(adapter.drain() == 0)
    }

    // MARK: - Native

    @Test func nativeAdapterReceivesAudioOnlyWhileActive() {
        let feed = GaplessVisualizerFeed()
        let source = VisualizerPCMSource()
        let adapter = GaplessNativeVisualizerAdapter(feed: feed, source: source)

        feed.deliver(Self.makeBuffer(frames: 1_024))
        #expect(adapter.drain() == 0)

        adapter.activate()
        feed.deliver(Self.makeBuffer(frames: 1_024))
        #expect(adapter.drain() == 1_024)
        // The samples reached the real Native source, not just the adapter.
        #expect(source.stats.producedFrames > 0)

        adapter.deactivate()
        feed.deliver(Self.makeBuffer(frames: 1_024))
        #expect(adapter.drain() == 0)
    }

    // MARK: - Lifecycle

    /// Switching Classic → Native and back must never touch the tap or the graph.
    @Test func switchingBetweenVisualizersKeepsOneTapInstalled() {
        let engine = PersistentGaplessEngine()
        engine.installVisualizerFeed()
        defer { engine.uninstallVisualizerFeed() }
        let classic = GaplessClassicVisualizerAdapter(feed: engine.visualizerFeed,
                                                      sampleRate: Self.sampleRate)
        let native = GaplessNativeVisualizerAdapter(feed: engine.visualizerFeed,
                                                    source: VisualizerPCMSource())
        let playerBefore = ObjectIdentifier(engine.player)
        let mixerBefore = ObjectIdentifier(engine.outputMixer)

        classic.activate()
        classic.deactivate()
        native.activate()
        native.deactivate()
        classic.activate()

        #expect(engine.visualizerFeed.isInstalled)
        #expect(engine.visualizerFeed.registeredConsumerCount == 2)
        #expect(ObjectIdentifier(engine.player) == playerBefore)
        #expect(ObjectIdentifier(engine.outputMixer) == mixerBefore)
    }

    @Test func rapidOpenCloseCyclesLeaveTheFeedHealthy() {
        let feed = GaplessVisualizerFeed()
        let adapter = GaplessClassicVisualizerAdapter(feed: feed, sampleRate: Self.sampleRate)

        for _ in 0..<50 {
            adapter.activate()
            feed.deliver(Self.makeBuffer(frames: 512))
            adapter.drain()
            adapter.deactivate()
        }

        #expect(feed.registeredConsumerCount == 1)
        #expect(feed.stats.contendedCallbacks == 0)
    }

    /// Both visualizers active at once see the same audio without competing for it.
    @Test func bothAdaptersCanConsumeConcurrently() {
        let feed = GaplessVisualizerFeed()
        let classic = GaplessClassicVisualizerAdapter(feed: feed, sampleRate: Self.sampleRate)
        let native = GaplessNativeVisualizerAdapter(feed: feed, source: VisualizerPCMSource())
        classic.activate()
        native.activate()

        feed.deliver(Self.makeBuffer(frames: 1_024))

        #expect(classic.drain() == 1_024)
        #expect(native.drain() == 1_024)
    }

    /// Audio keeps flowing across a track boundary; the adapter sees one continuous stream and
    /// nothing is reinstalled or reset.
    @Test func adaptersAreContinuousAcrossTrackBoundaries() {
        let feed = GaplessVisualizerFeed()
        let adapter = GaplessNativeVisualizerAdapter(feed: feed, source: VisualizerPCMSource())
        adapter.activate()

        var total = 0
        for _ in 0..<16 {                    // four "tracks" of four buffers
            feed.deliver(Self.makeBuffer(frames: 1_024))
            total += adapter.drain()
        }

        #expect(total == 16 * 1_024)
        #expect(feed.isInstalled == false)   // never installed on a node in this test
        #expect(feed.registeredConsumerCount == 1)
    }
}

/// Engine selection and fallback recording.
@MainActor
struct GaplessEngineSelectorTests {

    @Test func defaultsToThePersistentEngine() {
        let selector = GaplessEngineSelector()

        #expect(selector.selection == .persistentGapless)
    }

    /// A fallback must never happen under a playing track — swapping engines mid-track would cut the
    /// output stream, which is the defect this architecture exists to remove.
    @Test func fallbackIsRefusedWhileATrackIsAudible() {
        let selector = GaplessEngineSelector()
        selector.isTrackAudible = true

        let switched = selector.requestFallback(itemID: "a", reason: .decoderFailure)

        #expect(!switched)
        #expect(selector.selection == .persistentGapless)
        // The reason is still recorded, so the attempt is visible rather than lost.
        #expect(selector.reasons(forItemID: "a") == [.decoderFailure])
    }

    @Test func fallbackIsAllowedAtABoundary() {
        let selector = GaplessEngineSelector()
        selector.isTrackAudible = false

        #expect(selector.requestFallback(itemID: "a", reason: .unsupportedSource))
        #expect(selector.selection == .queuePlayerFallback)
        #expect(selector.restorePersistentEngine())
        #expect(selector.selection == .persistentGapless)
    }

    /// Capability follows what preparation actually discovered about the file.
    @Test(arguments: [
        (GaplessTrim.Reason.wholeFile, true),
        (.lameGaplessHeader, true),
        (.mp3WithoutGaplessMetadata, false)
    ])
    func capabilityFollowsTheTrimOutcome(scenario: (reason: GaplessTrim.Reason, capable: Bool)) {
        let capability = GaplessCapability.evaluate(trimReason: scenario.reason)

        #expect(capability.isGaplessCapable == scenario.capable)
        if !scenario.capable { #expect(capability.reason == .unsupportedSource) }
    }
}
