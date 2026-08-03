import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Can the persistent graph actually run in **real time** inside the test host?
///
/// This is a capability probe, not a feature test. Every gapless proof so far has used offline
/// manual rendering; the real-time path is a different mode with different failure modes (audio
/// session, output device, render thread). If real-time playback cannot start here, the real-time
/// backend cannot be proven by automated tests at all and that has to be known before designing
/// around it — so this test reports the capability rather than assuming it.
@MainActor
struct GaplessRealTimeProbeTests {

    /// Start the persistent graph for real and confirm the render clock advances.
    @Test func persistentGraphCanStartAndAdvanceInRealTime() async throws {
        let engine = PersistentGaplessEngine()
        #if os(iOS)
        // Explicit activation — the same step production will require. Nothing before this point
        // may touch the session.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        defer { try? session.setActive(false) }
        #endif

        let format = engine.renderFormat
        let frames = AVAudioFrameCount(format.sampleRate / 10)          // 100 ms
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            Issue.record("could not allocate buffer")
            return
        }
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            for i in 0..<Int(frames) {
                buffer.floatChannelData![channel][i] =
                    0.2 * Float(sin(2.0 * .pi * 220.0 * Double(i) / format.sampleRate))
            }
        }

        do {
            try engine.engine.start()
        } catch {
            // A test host with no usable output device cannot prove the real-time path. Report it
            // as a capability result instead of failing for the wrong reason.
            Issue.record("real-time engine start unavailable in this host: \(error.localizedDescription)")
            return
        }
        defer { engine.engine.stop() }

        #expect(engine.engine.isRunning)

        engine.player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        engine.player.play()

        // Give the render thread real time to produce audio.
        try await Task.sleep(for: .milliseconds(250))

        let renderTime = engine.player.lastRenderTime
        #expect(renderTime != nil, "player produced no render time — real-time rendering did not run")
        if let renderTime, let playerTime = engine.player.playerTime(forNodeTime: renderTime) {
            // The decisive evidence: the node's own sample clock advanced.
            #expect(playerTime.sampleTime > 0,
                    "player sample time did not advance (\(playerTime.sampleTime))")
        }
    }
}
