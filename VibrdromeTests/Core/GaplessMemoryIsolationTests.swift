import AVFoundation
import Foundation
import os.log
import Testing
@testable import Vibrdrome

/// Binary isolation of the post-warm-up retained-memory growth.
///
/// The accepted finding is bounded: *persistent playback exhibits repeatable post-warm-up retained
/// memory growth correlated with track transitions; the owning allocation is not yet identified.*
/// This file identifies it by removing one layer at a time, rather than by guessing at a suspect.
///
/// **One metric throughout.** Every figure here is `phys_footprint` from `task_vm_info`, the same
/// value iOS uses for memory limits. Baseline, windows and post-stop are all measured with it, so no
/// slope mixes resident size with footprint with live-heap bytes.
@MainActor
struct GaplessMemoryIsolationTests {
    static let sampleRate = 44_100.0
    static let trackFrames = 4_410          // 0.1 s — maximise transitions per second of test time

    /// Physical footprint in bytes. The single metric used for every measurement in this file.
    static func physFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    static func makeFixtures(count: Int, in directory: URL) throws -> [URL] {
        var urls: [URL] = []
        for index in 0..<count {
            let url = directory.appendingPathComponent("m\(index).wav")
            var samples = [Int16](repeating: 0, count: trackFrames)
            for i in 0..<trackFrames {
                samples[i] = Int16((max(-1, min(1, 0.5 * sin(2.0 * .pi * 300.0 * Double(i) / sampleRate))) * 32767).rounded())
            }
            try GaplessPipelineOfflineTests.writeWav(url: url, samples: samples, sampleRate: sampleRate)
            urls.append(url)
        }
        return urls
    }

    /// How a variant schedules one segment.
    enum SchedulingStyle: String {
        /// Open a fresh `AVAudioFile` per schedule and attach the production completion closure.
        case freshFilePerScheduleWithClosure
        /// Open a fresh file per schedule, but pass no completion handler.
        case freshFilePerScheduleNoClosure
        /// Reuse one already-open `AVAudioFile`, with the production closure.
        case reusedFileWithClosure
        /// Reuse one already-open file, no completion handler.
        case reusedFileNoClosure
    }

    /// Schedule `transitions` segments on a bare graph — no controller, no session, no diagnostics.
    /// This is the minimal backend: if the slope appears here, it belongs to the scheduling path.
    static func measureMinimal(style: SchedulingStyle, warmUp: Int, windows: Int,
                               windowSize: Int) throws -> (baseline: UInt64, samples: [UInt64]) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gmem-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try makeFixtures(count: 4, in: directory)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: 2, interleaved: false)!
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        defer { player.stop(); engine.stop() }
        player.play()

        let reusable = try urls.map { try AVAudioFile(forReading: $0) }
        let log = Logger(subsystem: "com.vibrdrome.app", category: "MemIsolation")

        func scheduleOne(_ index: Int) throws {
            let file: AVAudioFile
            switch style {
            case .freshFilePerScheduleWithClosure, .freshFilePerScheduleNoClosure:
                file = try AVAudioFile(forReading: urls[index % urls.count])
            case .reusedFileWithClosure, .reusedFileNoClosure:
                file = reusable[index % reusable.count]
            }
            let frames = AVAudioFrameCount(trackFrames)
            switch style {
            case .freshFilePerScheduleWithClosure, .reusedFileWithClosure:
                // The production closure shape: captures a Logger and a String label.
                let label = "seg-\(index)"
                let renderLog = log
                player.scheduleSegment(file, startingFrame: 0, frameCount: frames, at: nil,
                                       completionCallbackType: .dataRendered) { _ in
                    renderLog.debug("rendered \(label, privacy: .public)")
                }
            case .freshFilePerScheduleNoClosure, .reusedFileNoClosure:
                player.scheduleSegment(file, startingFrame: 0, frameCount: frames, at: nil,
                                       completionCallbackType: .dataRendered, completionHandler: nil)
            }
        }

        var scheduled = 0
        for _ in 0..<warmUp { try scheduleOne(scheduled); scheduled += 1 }
        let baseline = physFootprint()

        var samples: [UInt64] = []
        for _ in 0..<windows {
            for _ in 0..<windowSize { try scheduleOne(scheduled); scheduled += 1 }
            samples.append(physFootprint())
        }
        return (baseline, samples)
    }

    static func report(_ name: String, baseline: UInt64, samples: [UInt64],
                       transitionsPerWindow: Int) -> Double {
        let growthMB = Double(Int64(samples.last ?? baseline) - Int64(baseline)) / 1_048_576
        let total = transitionsPerWindow * samples.count
        let perTransitionKB = total > 0 ? growthMB * 1024 / Double(total) : 0
        let windowText = samples.map { String(format: "%.1f", Double($0) / 1_048_576) }
            .joined(separator: " → ")
        print(String(format: "MEM %-38@ base %7.1f MB  [%@]  growth %7.2f MB  %6.1f KB/transition",
                     name as NSString, Double(baseline) / 1_048_576, windowText as NSString,
                     growthMB, perTransitionKB))
        return perTransitionKB
    }

    // MARK: - Minimal backend: is the slope in the scheduling path at all?

    /// Four scheduling styles on a bare graph. If `freshFile*` grows and `reusedFile*` does not, the
    /// owner is the per-schedule file. If both grow only with a closure, the owner is the closure.
    @Test func minimalBackendIsolatesTheSchedulingPath() throws {
        let warmUp = 200, windows = 5, windowSize = 200
        var results: [(SchedulingStyle, Double)] = []
        for style in [SchedulingStyle.freshFilePerScheduleWithClosure,
                      .freshFilePerScheduleNoClosure,
                      .reusedFileWithClosure,
                      .reusedFileNoClosure] {
            let measured = try Self.measureMinimal(style: style, warmUp: warmUp,
                                                   windows: windows, windowSize: windowSize)
            let perTransition = Self.report(style.rawValue, baseline: measured.baseline,
                                            samples: measured.samples,
                                            transitionsPerWindow: windowSize)
            results.append((style, perTransition))
        }
        // Reported for diagnosis; the assertion that matters lands in the regression test once the
        // owner is proven.
        #expect(results.count == 4)
    }

    // MARK: - Regression: the proven owner stays bounded

    /// The fix, asserted rather than described: the backend keeps a bounded set of open files
    /// instead of opening one per schedule.
    ///
    /// Guards the exact defect that was measured — under Repeat All the same few URLs come round
    /// again and again, and opening a decoder for each pass grew the footprint by ~46 KB every
    /// transition with no upper bound.
    @Test func openFilesStayBoundedAcrossManyTransitions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gmemreg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try Self.makeFixtures(count: 4, in: directory)

        var files: [String: URL] = [:]
        var songIDs: [String] = []
        for (index, url) in urls.enumerated() {
            files["s\(index)"] = url
            songIDs.append("s\(index)")
        }
        let session = GaplessPlaybackSession(sampleRate: Self.sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = Double(Self.trackFrames) / Self.sampleRate }
        session.setRepeatMode(.all)

        let backend = GaplessRealTimeBackend()
        #if os(iOS)
        backend.activateAudioSession = {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try audio.setActive(true)
        }
        #endif
        let controller = GaplessPlaybackController(
            session: session, backend: backend,
            preparer: GaplessTrackPreparer(provider: GaplessLocalFileProvider(filesByTrackID: files),
                                           renderSampleRate: Self.sampleRate))
        defer { controller.stop() }

        try await controller.play()
        let deadline = Date().addingTimeInterval(25)
        var peakOpenFiles = 0
        var peakSegments = 0
        while Date() < deadline {
            await controller.tick()
            peakOpenFiles = max(peakOpenFiles, backend.openFileCount)
            peakSegments = max(peakSegments, backend.scheduledSegments.count)
            try? await Task.sleep(for: .milliseconds(4))
        }
        let transitions = controller.observedBoundaries.count

        #expect(transitions > 40, "not enough transitions to be meaningful: \(transitions)")
        // Open files never exceed the cache bound, however many times a URL is replayed.
        #expect(peakOpenFiles <= GaplessRealTimeBackend.maximumOpenFiles,
                "open files peaked at \(peakOpenFiles)")
        // It also cannot exceed the number of distinct sources.
        #expect(peakOpenFiles <= urls.count)
        // The scheduled tail stays at window depth rather than accumulating.
        #expect(peakSegments <= controller.window.size + 1, "segments peaked at \(peakSegments)")

        // Stop releases the cache entirely.
        controller.stop()
        await backend.settleTransport()
        let snap = await backend.domainSnapshotForTesting
        #expect(snap.openFiles == 0)
        #expect(snap.scheduledSegments == 0)
    }

    // MARK: - Application layer: do the diagnostic histories contribute?

    /// The controller and session keep append-only histories. Measured directly rather than assumed
    /// negligible: a `GaplessBoundaryEvent` is small, but "small × unbounded" is still unbounded.
    @Test func diagnosticHistoriesGrowthIsMeasured() throws {
        let transitions = 5_000
        var boundaries: [GaplessBoundaryEvent] = []
        var events: [GaplessPlaybackEvent] = []
        let baseline = Self.physFootprint()

        for index in 0..<transitions {
            boundaries.append(GaplessBoundaryEvent(
                playInstance: GaplessPlayInstanceID(rawValue: UInt64(index)),
                itemID: GaplessQueueItemID(rawValue: UInt64(index % 4)),
                songID: "song\(index % 4)", generation: 1, tailGeneration: 1,
                scheduledStartFrame: AVAudioFramePosition(index * 4_410),
                observedRenderFrame: AVAudioFramePosition(index * 4_410),
                replayGainLinear: 1, eqEnabled: true, visualizerFeedInstalled: true))
            events.append(.becameAudible(itemID: GaplessQueueItemID(rawValue: UInt64(index % 4)),
                                         songID: "song\(index % 4)",
                                         atFrame: AVAudioFramePosition(index * 4_410)))
        }
        let after = Self.physFootprint()
        let growthKB = Double(Int64(after) - Int64(baseline)) / 1_024
        print(String(format: "MEM %-38@ %d entries → %.1f KB total, %.3f KB/transition",
                     "diagnostic histories" as NSString, transitions, growthKB,
                     growthKB / Double(transitions)))
        // Kept alive so the optimiser cannot discard them before measurement.
        #expect(boundaries.count == transitions)
        #expect(events.count == transitions)
    }
}
