import AVFoundation
import Foundation
import os.log
import Testing
@testable import Vibrdrome

/// Completion-handler ownership matrix.
///
/// The confirmed finding is that post-warm-up growth needs **both** a newly opened `AVAudioFile` and
/// a scheduling completion closure; either alone is flat. This file determines which of the two the
/// node actually holds, using direct lifetime evidence rather than footprint inference:
///
/// - **File lifetime** — every scheduled file is registered in a weak box, so a live count is the
///   number of boxes whose reference is still non-nil. No wrapper is passed to AVFoundation, so the
///   measurement cannot itself change what is retained.
/// - **Closure lifetime** — each closure captures a sentinel whose `deinit` increments a counter, so
///   outstanding closures are created-minus-released. A closure the node never frees is visible
///   directly.
///
/// One metric for memory throughout: `phys_footprint`.
@MainActor
struct GaplessCallbackOwnershipTests {
    static let sampleRate = 44_100.0
    /// 10 ms per segment, so 1000 segments is ~10 s of audio and every callback can actually fire.
    static let segmentFrames = 441

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

    static func openFileDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
    }

    /// Holds a weak reference so a live-file count can be taken without retaining anything.
    final class WeakFileBox {
        weak var file: AVAudioFile?
        let id: Int
        init(_ file: AVAudioFile, id: Int) { self.file = file; self.id = id }
        var isAlive: Bool { file != nil }
    }

    /// Captured by a completion closure; its `deinit` reports that the closure was released.
    final class ClosureSentinel {
        private let onRelease: @Sendable () -> Void
        init(onRelease: @escaping @Sendable () -> Void) { self.onRelease = onRelease }
        deinit { onRelease() }
    }

    /// Thread-safe counters shared with closures that run off the main actor.
    final class Counters: @unchecked Sendable {
        private let lock = NSLock()
        private var _callbacks = 0
        private var _released = 0
        func callback() { lock.lock(); _callbacks += 1; lock.unlock() }
        func release() { lock.lock(); _released += 1; lock.unlock() }
        var callbacks: Int { lock.lock(); defer { lock.unlock() }; return _callbacks }
        var released: Int { lock.lock(); defer { lock.unlock() }; return _released }
    }

    enum Variant: String, CaseIterable {
        case noClosure                      // 1
        case productionClosureRendered      // 2 — Logger + String label, .dataRendered
        case minimalClosureRendered         // 3 — captures only immutable IDs
        case minimalClosureWeakBackend      // 4 — plus a weak backend reference
        case minimalClosureConsumed         // 5 — .dataConsumed
        case minimalClosurePlayedBack       // 7 — .dataPlayedBack
        // (.dataRendered with a minimal closure is variant 3, so 6 is covered.)

        var callbackType: AVAudioPlayerNodeCompletionCallbackType {
            switch self {
            case .minimalClosureConsumed: return .dataConsumed
            case .minimalClosurePlayedBack: return .dataPlayedBack
            default: return .dataRendered
            }
        }
        var usesClosure: Bool { self != .noClosure }
    }

    struct Result {
        let variant: Variant
        let footprintGrowthMB: Double
        let perTransitionKB: Double
        let liveFilesAtEnd: Int
        let peakLiveFiles: Int
        let liveFilesAfterSettle: Int
        let outstandingClosures: Int
        let callbacks: Int
        let descriptorGrowth: Int
        let scheduledCount: Int
    }

    static func run(variant: Variant, transitions: Int, warmUp: Int) async throws -> Result {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A distinct file per source so each schedule genuinely opens a fresh AVAudioFile.
        var urls: [URL] = []
        for index in 0..<8 {
            let url = directory.appendingPathComponent("c\(index).wav")
            var samples = [Int16](repeating: 0, count: segmentFrames)
            for i in 0..<segmentFrames {
                samples[i] = Int16((max(-1, min(1, 0.5 * sin(2.0 * .pi * 400.0 * Double(i) / sampleRate))) * 32767).rounded())
            }
            try GaplessPipelineOfflineTests.writeWav(url: url, samples: samples, sampleRate: sampleRate)
            urls.append(url)
        }

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

        let counters = Counters()
        var boxes: [WeakFileBox] = []
        var created = 0
        let log = Logger(subsystem: "com.vibrdrome.app", category: "CallbackMatrix")

        func scheduleOne(_ index: Int, track: Bool) throws {
            let file = try AVAudioFile(forReading: urls[index % urls.count])
            if track { boxes.append(WeakFileBox(file, id: index)) }
            let frames = AVAudioFrameCount(segmentFrames)

            guard variant.usesClosure else {
                player.scheduleSegment(file, startingFrame: 0, frameCount: frames, at: nil,
                                       completionCallbackType: variant.callbackType,
                                       completionHandler: nil)
                return
            }

            if track { created += 1 }
            let sentinel = track ? ClosureSentinel(onRelease: { [counters] in counters.release() }) : nil
            switch variant {
            case .productionClosureRendered:
                // Exactly the production shape: a Logger and an interpolated String label.
                let label = "seg-\(index)"
                let renderLog = log
                player.scheduleSegment(file, startingFrame: 0, frameCount: frames, at: nil,
                                       completionCallbackType: variant.callbackType) { [counters] _ in
                    _ = sentinel
                    renderLog.debug("rendered \(label, privacy: .public)")
                    counters.callback()
                }
            case .minimalClosureWeakBackend:
                weak var weakPlayer = player
                let token = UInt64(index)
                player.scheduleSegment(file, startingFrame: 0, frameCount: frames, at: nil,
                                       completionCallbackType: variant.callbackType) { [counters] _ in
                    _ = sentinel
                    _ = token
                    _ = weakPlayer
                    counters.callback()
                }
            default:
                // Minimal: only immutable scalar identity crosses into the closure.
                let token = UInt64(index)
                player.scheduleSegment(file, startingFrame: 0, frameCount: frames, at: nil,
                                       completionCallbackType: variant.callbackType) { [counters] _ in
                    _ = sentinel
                    _ = token
                    counters.callback()
                }
            }
        }

        var index = 0
        for _ in 0..<warmUp { try scheduleOne(index, track: false); index += 1 }
        // Let the warm-up drain so the baseline is taken on a settled graph.
        try? await Task.sleep(for: .milliseconds(500))
        let baseline = physFootprint()
        let descriptorsBefore = openFileDescriptorCount()

        var peakLive = 0
        for window in 0..<5 {
            for _ in 0..<(transitions / 5) { try scheduleOne(index, track: true); index += 1 }
            peakLive = max(peakLive, boxes.filter(\.isAlive).count)
            _ = window
            try? await Task.sleep(for: .milliseconds(200))
        }

        // Let every scheduled segment finish playing so all callbacks can fire.
        let drainDeadline = Date().addingTimeInterval(30)
        while Date() < drainDeadline, counters.callbacks < (variant.usesClosure ? transitions : 0) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(500))

        let footprintAfter = physFootprint()
        let liveAtEnd = boxes.filter(\.isAlive).count
        let descriptorsAfter = openFileDescriptorCount()

        // Stop discards pending schedules; then settle and re-count.
        player.stop()
        try? await Task.sleep(for: .seconds(2))
        let liveAfterSettle = boxes.filter(\.isAlive).count

        let growthMB = Double(Int64(footprintAfter) - Int64(baseline)) / 1_048_576
        return Result(variant: variant, footprintGrowthMB: growthMB,
                      perTransitionKB: growthMB * 1024 / Double(transitions),
                      liveFilesAtEnd: liveAtEnd, peakLiveFiles: peakLive,
                      liveFilesAfterSettle: liveAfterSettle,
                      outstandingClosures: created - counters.released,
                      callbacks: counters.callbacks,
                      descriptorGrowth: descriptorsAfter - descriptorsBefore,
                      scheduledCount: transitions)
    }

    /// Rules out the competing explanation for `liveFiles end == scheduled`: are the files genuinely
    /// retained by the node, or merely autoreleased and not yet drained?
    ///
    /// Three probes, no `stop()` in any of them:
    ///   A. schedule inside an explicit autorelease pool per item, then settle
    ///   B. schedule normally, then settle across several runloop turns
    ///   C. schedule normally, settle, then stop
    /// If A or B reach zero, the objects were autoreleased and the fix is pool placement. If only C
    /// reaches zero, the node retains them for the life of the play session.
    @Test func autoreleaseVersusRetentionProbe() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcbp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var urls: [URL] = []
        for index in 0..<4 {
            let url = directory.appendingPathComponent("p\(index).wav")
            var samples = [Int16](repeating: 0, count: Self.segmentFrames)
            for i in 0..<Self.segmentFrames {
                samples[i] = Int16((max(-1, min(1, 0.5 * sin(2.0 * .pi * 400.0 * Double(i) / Self.sampleRate))) * 32767).rounded())
            }
            try GaplessPipelineOfflineTests.writeWav(url: url, samples: samples, sampleRate: Self.sampleRate)
            urls.append(url)
        }

        func probe(label: String, usePool: Bool, thenStop: Bool) async throws -> (Int, Int) {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
                                       channels: 2, interleaved: false)!
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.prepare()
            try engine.start()
            defer { player.stop(); engine.stop() }
            player.play()

            var boxes: [WeakFileBox] = []
            for index in 0..<40 {
                if usePool {
                    try autoreleasepool {
                        let file = try AVAudioFile(forReading: urls[index % urls.count])
                        boxes.append(WeakFileBox(file, id: index))
                        player.scheduleSegment(file, startingFrame: 0,
                                               frameCount: AVAudioFrameCount(Self.segmentFrames),
                                               at: nil, completionCallbackType: .dataRendered,
                                               completionHandler: nil)
                    }
                } else {
                    let file = try AVAudioFile(forReading: urls[index % urls.count])
                    boxes.append(WeakFileBox(file, id: index))
                    player.scheduleSegment(file, startingFrame: 0,
                                           frameCount: AVAudioFrameCount(Self.segmentFrames),
                                           at: nil, completionCallbackType: .dataRendered,
                                           completionHandler: nil)
                }
            }
            // Let all 40 segments (0.4 s of audio) finish and several runloop turns pass.
            for _ in 0..<20 { try? await Task.sleep(for: .milliseconds(100)) }
            let liveBeforeStop = boxes.filter(\.isAlive).count
            if thenStop {
                player.stop()
                for _ in 0..<10 { try? await Task.sleep(for: .milliseconds(100)) }
            }
            let liveAfter = boxes.filter(\.isAlive).count
            print("CBPROBE \(label): live before stop \(liveBeforeStop) / 40, after \(liveAfter)")
            return (liveBeforeStop, liveAfter)
        }

        let poolResult = try await probe(label: "A autoreleasepool, no stop", usePool: true, thenStop: false)
        let plainResult = try await probe(label: "B plain, no stop", usePool: false, thenStop: false)
        let stopResult = try await probe(label: "C plain, then stop", usePool: false, thenStop: true)

        // Recorded as evidence; the interpretation is in the report, not an assertion here.
        #expect(poolResult.0 >= 0)
        #expect(plainResult.0 >= 0)
        #expect(stopResult.1 >= 0)
    }

    /// The matrix. Reports every variant so the owner is identified by evidence, not by elimination.
    @Test func completionHandlerOwnershipMatrix() async throws {
        let transitions = 500
        var results: [Result] = []
        for variant in Variant.allCases {
            let result = try await Self.run(variant: variant, transitions: transitions, warmUp: 100)
            results.append(result)
            print(String(format: "CB %-30@ growth %7.2f MB (%6.1f KB/tx)  liveFiles end %4d peak %4d settled %4d  outstandingClosures %4d  callbacks %4d  fdΔ %3d",
                         variant.rawValue as NSString, result.footprintGrowthMB,
                         result.perTransitionKB, result.liveFilesAtEnd, result.peakLiveFiles,
                         result.liveFilesAfterSettle, result.outstandingClosures,
                         result.callbacks, result.descriptorGrowth))
        }

        // Evidence, not a pass/fail gate — the gate lands in the regression test once the owner is
        // fixed. What must hold is that the matrix actually produced measurements.
        #expect(results.count == Variant.allCases.count)
        for result in results where result.variant.usesClosure {
            #expect(result.callbacks > 0, "\(result.variant): no callbacks fired")
        }
    }
}
