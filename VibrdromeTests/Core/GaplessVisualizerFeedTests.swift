import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Tests for the shared persistent visualizer feed.
///
/// The property under test is *separation*: a visualizer is a consumer of audio, never a participant
/// in the audio path. Opening, closing, or switching visualizers must be invisible to playback, and
/// a stalled UI must lose frames rather than block the render thread or grow memory.
struct GaplessVisualizerFeedTests {
    static let sampleRate = 44_100.0
    static let partFrames = 44_100

    static func makeBuffer(frames: Int, amplitude: Float = 0.4, phaseOffset: Int = 0) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<2 {
            for i in 0..<frames {
                let n = Double(phaseOffset + i)
                buffer.floatChannelData![channel][i] =
                    amplitude * Float(sin(2.0 * .pi * 220.0 * n / sampleRate))
            }
        }
        return buffer
    }

    // MARK: - Tap lifetime

    /// The tap belongs to the engine, not to any visualizer.
    @Test func tapIsInstalledOnceAndSurvivesConsumerChurn() {
        let engine = PersistentGaplessEngine()
        engine.installVisualizerFeed()
        #expect(engine.visualizerFeed.isInstalled)

        // Open, close, and reopen visualizers repeatedly.
        for _ in 0..<3 {
            let classic = engine.visualizerFeed.addConsumer(identifier: "classic")
            classic.isActive = true
            engine.visualizerFeed.removeConsumer(identifier: "classic")
        }

        #expect(engine.visualizerFeed.isInstalled)          // never removed by a visualizer closing
        engine.uninstallVisualizerFeed()
        #expect(!engine.visualizerFeed.isInstalled)
    }

    @Test func installingTwiceDoesNotReinstallTheTap() {
        let engine = PersistentGaplessEngine()
        engine.installVisualizerFeed()
        engine.installVisualizerFeed()          // would throw inside AVAudioEngine if it reinstalled

        #expect(engine.visualizerFeed.isInstalled)
        engine.uninstallVisualizerFeed()
    }

    @Test func consumersRegisterAndDeregisterWithoutDuplicates() {
        let feed = GaplessVisualizerFeed()

        feed.addConsumer(identifier: "classic")
        feed.addConsumer(identifier: "classic")          // same id must not duplicate
        feed.addConsumer(identifier: "native")

        #expect(feed.registeredConsumerCount == 2)
        feed.removeConsumer(identifier: "classic")
        #expect(feed.registeredConsumerCount == 1)
        #expect(feed.consumer(identifier: "native") != nil)
    }

    // MARK: - Delivery and gating

    @Test func activeConsumerReceivesSamplesAndInactiveOneDoesNot() {
        let feed = GaplessVisualizerFeed()
        let classic = feed.addConsumer(identifier: "classic")
        let native = feed.addConsumer(identifier: "native")
        classic.isActive = true
        native.isActive = false

        feed.deliver(Self.makeBuffer(frames: 512))

        var scratch = [Float](repeating: 0, count: 512 * 2)
        let classicFrames = scratch.withUnsafeMutableBufferPointer {
            classic.buffer.read(into: $0.baseAddress!, maxFrames: 512)
        }
        let nativeFrames = scratch.withUnsafeMutableBufferPointer {
            native.buffer.read(into: $0.baseAddress!, maxFrames: 512)
        }

        #expect(classicFrames == 512)
        // A closed visualizer costs nothing downstream — no samples, no work.
        #expect(nativeFrames == 0)
    }

    /// Both visualizers can be active at once and each sees the same audio, because each has its own
    /// ring rather than competing for one.
    @Test func classicAndNativeConsumeTheSameSamplesIndependently() {
        let feed = GaplessVisualizerFeed()
        let classic = feed.addConsumer(identifier: "classic")
        let native = feed.addConsumer(identifier: "native")
        classic.isActive = true
        native.isActive = true

        feed.deliver(Self.makeBuffer(frames: 256))

        var classicSamples = [Float](repeating: 0, count: 256 * 2)
        var nativeSamples = [Float](repeating: 0, count: 256 * 2)
        let classicFrames = classicSamples.withUnsafeMutableBufferPointer {
            classic.buffer.read(into: $0.baseAddress!, maxFrames: 256)
        }
        let nativeFrames = nativeSamples.withUnsafeMutableBufferPointer {
            native.buffer.read(into: $0.baseAddress!, maxFrames: 256)
        }

        #expect(classicFrames == 256)
        #expect(nativeFrames == 256)
        #expect(classicSamples == nativeSamples)
        // Draining one must not consume the other's data.
        #expect(classic.buffer.stats.fillFrames == 0)
        #expect(native.buffer.stats.fillFrames == 0)
    }

    /// Switching from Classic to Native is a consumer change, nothing more.
    @Test func switchingVisualizersLeavesTheTapAndPlaybackAlone() {
        let engine = PersistentGaplessEngine()
        engine.installVisualizerFeed()
        defer { engine.uninstallVisualizerFeed() }
        let playerBefore = ObjectIdentifier(engine.player)
        let mixerBefore = ObjectIdentifier(engine.outputMixer)

        let classic = engine.visualizerFeed.addConsumer(identifier: "classic")
        classic.isActive = true
        classic.isActive = false
        let native = engine.visualizerFeed.addConsumer(identifier: "native")
        native.isActive = true

        #expect(engine.visualizerFeed.isInstalled)
        #expect(ObjectIdentifier(engine.player) == playerBefore)
        #expect(ObjectIdentifier(engine.outputMixer) == mixerBefore)
    }

    // MARK: - Bounded behaviour

    /// A stalled UI consumer must lose the oldest frames, not grow memory without limit.
    @Test func stalledConsumerDropsOldFramesInsteadOfGrowing() {
        let feed = GaplessVisualizerFeed()
        let consumer = feed.addConsumer(identifier: "stalled")
        consumer.isActive = true

        // Push far more than the ring can hold, never reading.
        let capacity = consumer.buffer.frameCapacity
        var pushed = 0
        while pushed < capacity * 3 {
            feed.deliver(Self.makeBuffer(frames: 1_024, phaseOffset: pushed))
            pushed += 1_024
        }

        let stats = consumer.buffer.stats
        #expect(stats.fillFrames <= capacity)            // bounded
        #expect(stats.overflowFrames > 0)                // and the loss is counted, not hidden
        #expect(feed.stats.framesDelivered == UInt64(pushed))
    }

    /// A closed visualizer leaves no stale audio behind for the next time it opens.
    @Test func reopeningAConsumerDoesNotReplayStaleAudio() {
        let feed = GaplessVisualizerFeed()
        let consumer = feed.addConsumer(identifier: "classic")
        consumer.isActive = true
        feed.deliver(Self.makeBuffer(frames: 512))

        consumer.isActive = false
        consumer.buffer.reset()                          // what closing a visualizer does
        feed.deliver(Self.makeBuffer(frames: 512))       // audio keeps flowing while it is closed
        consumer.isActive = true

        #expect(consumer.buffer.stats.fillFrames == 0)   // nothing stale waiting
    }

    // MARK: - Continuity across track boundaries

    /// The feed must be indifferent to track boundaries: samples arrive as one continuous stream and
    /// nothing is reinstalled, reset, or interrupted at a join.
    @Test func feedIsContinuousAcrossFourTrackBoundaries() {
        let feed = GaplessVisualizerFeed()
        let consumer = feed.addConsumer(identifier: "native")
        consumer.isActive = true
        let chunk = 1_024
        let chunksPerTrack = 8

        var delivered = 0
        var drained: [Float] = []
        var scratch = [Float](repeating: 0, count: chunk * 2)
        for _ in 0..<(4 * chunksPerTrack) {
            feed.deliver(Self.makeBuffer(frames: chunk, phaseOffset: delivered))
            delivered += chunk
            let frames = scratch.withUnsafeMutableBufferPointer {
                consumer.buffer.read(into: $0.baseAddress!, maxFrames: chunk)
            }
            drained.append(contentsOf: scratch.prefix(frames * 2))
        }

        // Every frame arrived exactly once: no gap at a boundary, no duplicate.
        #expect(drained.count == delivered * 2)
        #expect(consumer.buffer.stats.overflowFrames == 0)
        #expect(feed.stats.callbackCount == UInt64(4 * chunksPerTrack))
        #expect(feed.stats.contendedCallbacks == 0)
    }

    // MARK: - Render-thread cost

    /// The callback must stay far away from the audio deadline. One buffer of 1024 frames at
    /// 44.1 kHz is ~23 ms of audio, so a copy measured in microseconds has enormous headroom.
    @Test func callbackCostStaysWellInsideTheAudioDeadline() {
        let feed = GaplessVisualizerFeed()
        let classic = feed.addConsumer(identifier: "classic")
        let native = feed.addConsumer(identifier: "native")
        classic.isActive = true
        native.isActive = true
        let buffer = Self.makeBuffer(frames: 1_024)

        for _ in 0..<200 { feed.deliver(buffer) }

        let stats = feed.stats
        let deadlineNanoseconds = UInt64(1_024.0 / Self.sampleRate * 1_000_000_000)
        #expect(stats.callbackCount == 200)
        #expect(stats.peakCallbackNanoseconds < deadlineNanoseconds / 4,
                "peak \(stats.peakCallbackNanoseconds) ns vs deadline \(deadlineNanoseconds) ns")
        #expect(stats.contendedCallbacks == 0)
    }

    /// With no consumers registered at all, the tap still runs and still costs almost nothing.
    @Test func feedWithNoConsumersDoesAlmostNoWork() {
        let feed = GaplessVisualizerFeed()
        let buffer = Self.makeBuffer(frames: 1_024)

        for _ in 0..<200 { feed.deliver(buffer) }

        #expect(feed.stats.callbackCount == 200)
        #expect(feed.hasActiveConsumer == false)
    }
}
