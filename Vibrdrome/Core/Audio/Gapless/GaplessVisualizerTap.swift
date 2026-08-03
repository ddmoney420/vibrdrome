import AVFoundation
import Foundation
import os.log

/// The single, permanent PCM tap that feeds the visualizers.
///
/// Preparation only at this checkpoint: the tap point and its lifetime rules are fixed here so the
/// visualizer unit can be built against them, but neither visualizer is wired up yet.
///
/// The rule that matters is **install once**. In the old playback path a visualizer opening or
/// closing changed the audio pipeline, which is how a UI action became an audio-path event. Here the
/// tap is installed on the persistent `outputMixer` when the engine starts and removed only when the
/// engine is torn down. Opening or closing a visualizer adds or removes a *consumer* — the tap, the
/// graph, and everything scheduled are untouched.
///
/// Placement is after gain and EQ, so the visualizers show what is actually heard rather than the
/// raw file.
///
/// Render-thread contract: the tap callback runs on a real-time thread. It must not allocate, lock,
/// wait, or call back into the main actor. Consumers therefore receive a bounded copy into
/// pre-allocated storage and do their own work elsewhere; a consumer that cannot keep up drops
/// frames rather than stalling the render thread.
final class GaplessVisualizerTap {
    /// Frames requested per callback. A bounded, fixed size keeps the render-thread work constant
    /// and lets consumers pre-allocate.
    static let bufferFrames: AVAudioFrameCount = 1_024

    /// Something that wants PCM — Classic (FFT) and Native both consume this same feed rather than
    /// each installing their own tap.
    protocol Consumer: AnyObject, Sendable {
        var isActive: Bool { get }
        /// Called on the audio render thread. Must return promptly and must not block.
        func receive(_ buffer: AVAudioPCMBuffer)
    }

    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessVisualizer")
    private weak var tappedNode: AVAudioNode?
    private var consumers: [Consumer] = []
    private(set) var isInstalled = false

    /// Install the tap once, for the life of the engine.
    func install(on node: AVAudioNode, format: AVAudioFormat) {
        guard !isInstalled else { return }
        tappedNode = node
        node.installTap(onBus: 0, bufferSize: Self.bufferFrames, format: format) { [weak self] buffer, _ in
            // Deliberately minimal: no allocation, no locking, no main-actor hops.
            guard let self else { return }
            for consumer in self.consumers where consumer.isActive {
                consumer.receive(buffer)
            }
        }
        isInstalled = true
    }

    /// Remove the tap. Called only when the engine itself is torn down — never because a visualizer
    /// closed.
    func uninstall() {
        guard isInstalled else { return }
        tappedNode?.removeTap(onBus: 0)
        isInstalled = false
    }

    /// Add a consumer. Does not touch the tap or the graph, so opening a visualizer mid-track is
    /// invisible to playback.
    func addConsumer(_ consumer: Consumer) {
        guard !consumers.contains(where: { $0 === consumer }) else { return }
        consumers.append(consumer)
    }

    /// Remove a consumer. The tap keeps running with no consumers — that is intentional, because
    /// re-installing a tap is exactly the per-item pipeline churn this design removes.
    func removeConsumer(_ consumer: Consumer) {
        consumers.removeAll { $0 === consumer }
    }

    /// Whether any consumer currently wants data. Callers may use this to skip their own work, but
    /// must not use it to decide whether the tap exists.
    var hasActiveConsumer: Bool { consumers.contains { $0.isActive } }
}
