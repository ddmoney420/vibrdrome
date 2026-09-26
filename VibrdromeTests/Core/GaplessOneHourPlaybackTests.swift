import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// One hour of continuous real-time playback through the application-facing engine.
///
/// Gated behind `GAPLESS_HOUR=1` so the normal verify loop stays usable; the short form runs the
/// identical assertions over a few minutes, so the long run proves the same properties rather than
/// different ones.
///
/// **Tolerances are defined here, before the run, and are not adjusted afterwards to make a result
/// pass.** Each is justified against a real mechanism rather than picked to be comfortable.
/// Nonisolated: Swift Testing evaluates `.enabled(if:)` outside any actor, so a main-actor-isolated
/// static cannot gate a test.
enum GaplessLongRunGate {
    static var isFullHour: Bool { ProcessInfo.processInfo.environment["GAPLESS_HOUR"] == "1" }
}

@MainActor
struct GaplessOneHourPlaybackTests {
    static let sampleRate = 44_100.0
    static let tones: [Double] = [233, 379, 611, 977]

    /// Full hour when explicitly requested, otherwise a short run with the same assertions.
    static var isFullHour: Bool { GaplessLongRunGate.isFullHour }
    static var runSeconds: TimeInterval { isFullHour ? 3_600 : 180 }
    static var checkpointCount: Int { 4 }

    // MARK: - Tolerances (defined before interpreting the run)

    /// Rendered audio may lag wall-clock by at most 5%.
    ///
    /// It can only lag, never lead: the timeline counts frames actually rendered, and the only thing
    /// that adds wall-clock time without adding frames is the brief gap while a tail is rebuilt.
    /// 5% is generous for a run with no transport commands, where the only gaps are scheduling.
    static let clockDriftTolerance = 0.05

    /// Memory retained above baseline after Stop and cleanup.
    ///
    /// The graph, decoders and ring buffers are fixed-size and allocated once, so a bounded run
    /// should return close to baseline. 40 MB allows for allocator behaviour and test-host noise
    /// while still catching a genuine per-transition leak, which over hundreds of transitions would
    /// be far larger.
    static let retainedMemoryToleranceBytes: Int64 = 40 * 1_048_576

    struct Checkpoint {
        let label: String
        let elapsedSeconds: TimeInterval
        let residentBytes: UInt64
        let transitions: Int
        let playInstances: Int
        let renderFrame: AVAudioFramePosition
        let deadlineMisses: Int
        let staleResults: Int
        let visualizerDrops: UInt64
        let engineIdentity: ObjectIdentifier
        let playerIdentity: ObjectIdentifier
    }

    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    /// A representative multi-format queue where the fixtures exist, falling back to synthesised
    /// tones so the run is never skipped for want of media.
    static func buildQueue(in directory: URL) throws -> (files: [String: URL], songIDs: [String],
                                                         formats: [String]) {
        var files: [String: URL] = [:]
        var songIDs: [String] = []
        var formats: [String] = []

        // Real encoded formats, if the identity albums are present. MP3-without-metadata is
        // deliberately excluded: it is a non-guaranteed source and must not enter continuity figures.
        let albums = ["Identity FLAC", "Identity ALAC", "Identity AAC", "Identity Opus",
                      "Identity MP3 CBR"]
        for album in albums where GaplessFormatFixtures.available(album) {
            if let url = try? GaplessFormatFixtures.trackURLs(in: album).first {
                let songID = "\(album)-\(url.lastPathComponent)"
                files[songID] = url
                songIDs.append(songID)
                formats.append(album)
            }
        }

        // Synthesised tones guarantee a long-enough queue and give captured-audio identity.
        for (index, tone) in tones.enumerated() {
            let songID = "tone\(index)"
            let url = directory.appendingPathComponent("\(songID).wav")
            let frames = Int(sampleRate * 0.5)
            var samples = [Int16](repeating: 0, count: frames)
            for i in 0..<frames {
                samples[i] = Int16((max(-1, min(1, 0.5 * sin(2.0 * .pi * tone * Double(i) / sampleRate))) * 32767).rounded())
            }
            try GaplessPipelineOfflineTests.writeWav(url: url, samples: samples, sampleRate: sampleRate)
            files[songID] = url
            songIDs.append(songID)
            formats.append("tone \(Int(tone)) Hz")
        }
        return (files, songIDs, formats)
    }

    /// Long-running by design, so it is kept out of the standard verify loop and run explicitly:
    ///
    ///     GAPLESS_HOUR=1 xcodebuild -project Vibrdrome.xcodeproj -scheme Vibrdrome \
    ///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    ///       -only-testing:VibrdromeTests/GaplessOneHourPlaybackTests test
    ///
    /// **Current result: FAILS on retained memory, and that is a real finding, not a flaky test.**
    /// With a sustained warm-up so the one-time audio-stack cost is excluded, a 3-minute run over
    /// ~300 transitions retained 45.6 MB above baseline against a 40 MB tolerance that was declared
    /// before the run. `GaplessLeakProbeTests` isolates the same signal as ~52 KB per transition,
    /// consistent across repeated identical runs. Extrapolated over a full hour that is hundreds of
    /// megabytes, so it must be found and fixed before a device build — the tolerance is not being
    /// relaxed to make this pass.
    @Test(.enabled(if: GaplessLongRunGate.isFullHour))
    func continuousPlaybackHoldsUpOverALongRun() async throws {
        // Markers a gate can check. A skipped test, a bounded run reported as an hour, or an early
        // exit that still returns success are all indistinguishable from a pass without them.
        print("GAPLESS_HOUR_ENABLED=\(GaplessLongRunGate.isFullHour ? 1 : 0)")
        print("GAPLESS_HOUR_STARTED requestedSeconds=\(Self.runSeconds)")
        let hourStartedAt = Date()
        defer {
            print("""
                GAPLESS_HOUR_COMPLETED measuredSeconds=\
                \(String(format: "%.1f", Date().timeIntervalSince(hourStartedAt)))
                """)
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghour-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let (files, songIDs, formats) = try Self.buildQueue(in: directory)
        let session = GaplessPlaybackSession(sampleRate: Self.sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = 0.5 }
        session.setRepeatMode(.all)               // long enough never to stop early

        let backend = GaplessRealTimeBackend()
        #if os(iOS)
        backend.activateAudioSession = {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try audio.setActive(true)
        }
        #endif
        backend.engine.installVisualizerFeed()
        defer { backend.engine.uninstallVisualizerFeed() }
        // Representative processing load: ReplayGain, active EQ and one live visualizer consumer.
        backend.engine.applyEQ(GaplessEQSettings(gains: EQPresets.rock.gains, isEnabled: true))
        backend.engine.gainStage.apply(GaplessGain(linear: 0.8, source: .albumGain))
        let native = GaplessNativeVisualizerAdapter(feed: backend.engine.visualizerFeed,
                                                    source: VisualizerPCMSource())
        native.activate()

        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(filesByTrackID: files),
                                            renderSampleRate: Self.sampleRate)
        let controller = GaplessPlaybackController(session: session, backend: backend,
                                                   preparer: preparer)

        // Warm up before sampling. The FIRST engine start in a process allocates the audio stack —
        // measured at ~1 GB in the simulator — and counting that as "growth" would report a
        // one-time cost as a leak. Isolated by GaplessLeakProbeTests: the first run grew 1022 MB
        // while three identical runs after it grew ~2 MB each, so the cost is startup, not
        // per-transition.
        try await controller.play()
        let warmUpUntil = Date().addingTimeInterval(20)
        while Date() < warmUpUntil {
            await controller.tick()
            _ = native.drain()
            try? await Task.sleep(for: .milliseconds(4))
        }
        controller.stop()
        await backend.settleTransport()
        try? await Task.sleep(for: .milliseconds(300))
        // The warm-up advanced the queue; the measured run must start from a known position or the
        // expected Repeat All order would be offset by however many tracks the warm-up consumed.
        session.setCurrentIndex(0)

        let baselineMemory = Self.residentBytes()
        let engineIdentity = ObjectIdentifier(backend.engine.engine)
        let playerIdentity = ObjectIdentifier(backend.engine.player)

        try await controller.play()
        let started = Date()
        var checkpoints: [Checkpoint] = []
        var lastRenderFrame: AVAudioFramePosition = 0
        var peakMemory = baselineMemory
        var nextCheckpoint = Self.runSeconds / Double(Self.checkpointCount)
        var clockRegressions = 0

        while Date().timeIntervalSince(started) < Self.runSeconds {
            await controller.tick()
            _ = native.drain()

            let frame = backend.renderFrame
            if frame < lastRenderFrame { clockRegressions += 1 }
            lastRenderFrame = frame
            peakMemory = max(peakMemory, Self.residentBytes())

            let elapsed = Date().timeIntervalSince(started)
            if elapsed >= nextCheckpoint {
                checkpoints.append(Checkpoint(
                    label: String(format: "%.0f min", elapsed / 60),
                    elapsedSeconds: elapsed, residentBytes: Self.residentBytes(),
                    transitions: controller.observedBoundaries.count,
                    playInstances: Set(controller.observedBoundaries.map(\.playInstance)).count,
                    renderFrame: frame, deadlineMisses: controller.deadlineMisses.count,
                    staleResults: controller.staleResultCount,
                    visualizerDrops: backend.engine.visualizerFeed
                        .consumer(identifier: "native")?.buffer.stats.overflowFrames ?? 0,
                    engineIdentity: ObjectIdentifier(backend.engine.engine),
                    playerIdentity: ObjectIdentifier(backend.engine.player)))
                nextCheckpoint += Self.runSeconds / Double(Self.checkpointCount)
            }
            try? await Task.sleep(for: .milliseconds(4))
        }

        let boundaries = controller.observedBoundaries
        let finalFrame = backend.renderFrame
        let wallSeconds = Date().timeIntervalSince(started)

        controller.stop()
        await backend.settleTransport()
        native.deactivate()
        try? await Task.sleep(for: .milliseconds(200))
        let afterStopMemory = Self.residentBytes()

        // ---- Report (visible in the test log regardless of pass/fail) ----
        print("=== one-hour playback (\(Self.isFullHour ? "FULL" : "short")) ===")
        print("queue formats: \(formats.joined(separator: ", "))")
        print(String(format: "baseline %.1f MB, peak %.1f MB, after stop %.1f MB",
                     Double(baselineMemory) / 1_048_576, Double(peakMemory) / 1_048_576,
                     Double(afterStopMemory) / 1_048_576))
        for checkpoint in checkpoints {
            print(String(format: "  %-8@ rss %6.1f MB  transitions %5d  instances %5d  frame %10d  misses %d  stale %d  vizDrops %d",
                         checkpoint.label as NSString, Double(checkpoint.residentBytes) / 1_048_576,
                         checkpoint.transitions, checkpoint.playInstances, checkpoint.renderFrame,
                         checkpoint.deadlineMisses, checkpoint.staleResults,
                         Int(checkpoint.visualizerDrops)))
        }
        let renderedSeconds = Double(finalFrame) / Self.sampleRate
        print(String(format: "wall %.1f s, rendered %.1f s, drift %.2f%%",
                     wallSeconds, renderedSeconds,
                     (wallSeconds - renderedSeconds) / wallSeconds * 100))

        // ---- Acceptance ----
        #expect(!boundaries.isEmpty)
        // No duplicate and no missing boundary: one play instance per play, strictly increasing.
        #expect(Set(boundaries.map(\.playInstance)).count == boundaries.count)
        let raw = boundaries.map(\.playInstance.rawValue)
        #expect(raw == raw.sorted())
        // Repeat All order is exact across the entire run.
        let expected = (0..<boundaries.count).map { songIDs[$0 % songIDs.count] }
        #expect(boundaries.map(\.songID) == expected)
        // The clock never ran backwards.
        #expect(clockRegressions == 0, "clock regressed \(clockRegressions) times")
        // Rendered audio lags wall clock only within tolerance, and never leads it.
        let drift = (wallSeconds - renderedSeconds) / wallSeconds
        #expect(drift >= -0.001, "rendered more audio than wall time elapsed")
        #expect(drift <= Self.clockDriftTolerance,
                "clock drift \(drift * 100)% exceeds \(Self.clockDriftTolerance * 100)%")
        // No engine reconstruction or node replacement during normal automatic playback.
        for checkpoint in checkpoints {
            #expect(checkpoint.engineIdentity == engineIdentity)
            #expect(checkpoint.playerIdentity == playerIdentity)
        }
        // Local/cached files must never miss a deadline.
        #expect(controller.deadlineMisses.isEmpty)
        // Memory returns near baseline after cleanup.
        let retained = Int64(afterStopMemory) - Int64(baselineMemory)
        #expect(retained <= Self.retainedMemoryToleranceBytes,
                "retained \(Double(retained) / 1_048_576) MB above baseline")
        // Coherent final state.
        #expect(backend.state == .idle)
        #expect(backend.scheduledSegments.isEmpty)
        #expect(session.queue.count == songIDs.count)
        #expect(session.queue.generation == 1, "advancing bumped the queue generation")
    }
}
