import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Separates one-time audio-stack allocation from genuine per-transition growth.
///
/// This exists because the one-hour harness first reported ~1 GB of "growth" and the obvious reading
/// — a leak — was wrong. Running the same workload four times shows the shape immediately:
///
///     run 1  120 transitions  1052.0 MB   8.767 MB/transition
///     run 2  120 transitions     6.4 MB   0.054 MB/transition
///     run 3  120 transitions     6.3 MB   0.052 MB/transition
///     run 4  120 transitions     6.3 MB   0.052 MB/transition
///
/// The first number is the process's one-time audio-stack cost; a per-transition leak would have
/// grown all four alike. What remains after warm-up is ~52 KB per transition, consistent to three
/// decimals across runs — small, but it does not level off, so over a long session it accumulates.
/// That residual is an open finding, not a measurement artefact.
@MainActor
struct GaplessLeakProbeTests {
    static let sampleRate = 44_100.0

    static func rss() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return r == KERN_SUCCESS ? info.resident_size : 0
    }

    /// Run N transitions with selected features on/off and report MB per transition.
    static func probe(label: String, seconds: TimeInterval, eq: Bool, gain: Bool,
                      visualizer: Bool) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gleak-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var files: [String: URL] = [:]
        var ids: [String] = []
        for i in 0..<4 {
            let url = dir.appendingPathComponent("s\(i).wav")
            let frames = Int(sampleRate * 0.5)
            var samples = [Int16](repeating: 0, count: frames)
            for j in 0..<frames { samples[j] = Int16(0.5 * 32767 * sin(2.0 * .pi * 300.0 * Double(j) / sampleRate)) }
            try GaplessPipelineOfflineTests.writeWav(url: url, samples: samples, sampleRate: sampleRate)
            files["s\(i)"] = url; ids.append("s\(i)")
        }
        let session = GaplessPlaybackSession(sampleRate: sampleRate)
        session.replaceQueue(songIDs: ids)
        for id in ids { session.songDurations[id] = 0.5 }
        session.setRepeatMode(.all)
        let backend = GaplessRealTimeBackend()
        #if os(iOS)
        backend.activateAudioSession = {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        }
        #endif
        var native: GaplessNativeVisualizerAdapter?
        if visualizer {
            backend.engine.installVisualizerFeed()
            native = GaplessNativeVisualizerAdapter(feed: backend.engine.visualizerFeed,
                                                    source: VisualizerPCMSource())
            native?.activate()
        }
        if eq { backend.engine.applyEQ(GaplessEQSettings(gains: EQPresets.rock.gains, isEnabled: true)) }
        if gain { backend.engine.gainStage.apply(GaplessGain(linear: 0.8, source: .albumGain)) }
        let controller = GaplessPlaybackController(
            session: session, backend: backend,
            preparer: GaplessTrackPreparer(provider: GaplessLocalFileProvider(filesByTrackID: files),
                                           renderSampleRate: sampleRate))
        let base = rss()
        try await controller.play()
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            await controller.tick()
            _ = native?.drain()
            try? await Task.sleep(for: .milliseconds(4))
        }
        let transitions = controller.observedBoundaries.count
        let openFiles = backend.openFileCount
        let end = rss()
        let growthMB = Double(Int64(end) - Int64(base)) / 1_048_576
        print(String(format: "PROBE %-28@ transitions %4d  growth %8.1f MB  perTransition %6.3f MB  openFiles %d  segments %d  boundaries %d",
                     label as NSString, transitions, growthMB,
                     transitions > 0 ? growthMB / Double(transitions) : 0,
                     openFiles, backend.scheduledSegments.count,
                     controller.observedBoundaries.count))
        controller.stop()
        await backend.settleTransport()
        if visualizer { backend.engine.uninstallVisualizerFeed() }
    }

    /// Four identical sustained runs. If growth is a one-time startup cost, run 1 is large and
    /// runs 2-4 are flat. If there is a per-transition leak, all four grow similarly.
    @Test func isolateGrowth() async throws {
        for round in 1...4 {
            try await Self.probe(label: "sustained run \(round)", seconds: 20,
                                 eq: true, gain: true, visualizer: true)
        }
        #expect(true)
    }
}
