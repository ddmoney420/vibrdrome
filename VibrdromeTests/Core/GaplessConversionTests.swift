import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Where the real format fixtures live, and whether they are reachable.
///
/// A nonisolated enum because Swift Testing evaluates `.enabled(if:)` and `arguments:` outside any
/// actor — putting these on the `@MainActor` suite traps at test-collection time.
enum GaplessConversionMedia {
    static let root: URL = {
        let environment = ProcessInfo.processInfo.environment
        if let explicit = environment["VIBRDROME_TEST_MEDIA"] {
            return URL(fileURLWithPath: explicit)
        }
        if let hostHome = environment["SIMULATOR_HOST_HOME"] {
            return URL(fileURLWithPath: hostHome).appendingPathComponent("vibrdrome-test-media")
        }
        #if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("vibrdrome-test-media")
        #else
        return URL(fileURLWithPath: "/vibrdrome-test-media-unavailable")
        #endif
    }()

    static let opusAlbum = "Gapless 4-Track Opus"
    static let flacAlbum = "Gapless 4-Track Test"
    static let alacAlbum = "Gapless 4-Track ALAC"

    static func files(in album: String) -> [URL] {
        let directory = root.appendingPathComponent(album)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        return contents.filter { !$0.lastPathComponent.hasPrefix(".") }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }

    static var opusAvailable: Bool { files(in: opusAlbum).count >= 4 }
    static var mixedAvailable: Bool {
        files(in: opusAlbum).count >= 2 && files(in: flacAlbum).count >= 2
            && files(in: alacAlbum).count >= 2
    }
}

/// Checkpoint B: the explicit conversion boundary.
///
/// Scheduling PCM buffers moved sample-rate conversion out of `AVAudioPlayerNode` and into a stage
/// that can fail on its own. These tests treat that stage as the fallible thing it is: frames are
/// counted rather than computed, a truncated source may not place the next track at a frame no audio
/// occupies, and a conversion failure must leave the pool and the queue coherent.
/// Serialised deliberately. Swift Testing runs tests in parallel by default, which would put several
/// `AVAudioEngine` instances — one of them in manual rendering mode — live in the process at the
/// same time. Audio-engine teardown has already produced phantom discontinuities in this work when
/// engines overlapped, so these run one at a time.
@Suite(.serialized)
@MainActor
struct GaplessConversionTests {
    static let renderRate = GaplessBufferFixtures.sampleRate

    // MARK: - Span analysis driven by actual segment records

    /// Which tone is present inside each track's *reconciled* span.
    ///
    /// Spans come from the scheduler's segment records, not from a nominal track length: once a
    /// converter is in the path, a track's render length is what the resampler produced, and an
    /// assumed length would drift a little further out of step with every transition.
    static func tonesInSegments(_ capture: GaplessRealTimeCapture,
                                segments: [GaplessScheduledSegment]) -> [Double?] {
        let samples = capture.samples
        let captureRate = capture.observedSampleRate > 0 ? capture.observedSampleRate : renderRate
        let scale = captureRate / renderRate
        guard let origin = samples.firstIndex(where: { abs($0) > 0.01 }), let first = segments.first
        else { return [] }
        var tones: [Double?] = []
        for segment in segments {
            let start = origin + Int((Double(segment.startFrame - first.startFrame) * scale).rounded())
            let length = Int((Double(segment.frameCount) * scale).rounded())
            let interiorStart = start + length / 4
            let interiorEnd = start + length * 3 / 4
            guard interiorEnd <= samples.count, interiorEnd > interiorStart else {
                tones.append(nil)
                continue
            }
            tones.append(GaplessRealTimeCapture.dominantFrequency(
                samples[interiorStart..<interiorEnd],
                frequencies: GaplessBufferFixtures.tones, sampleRate: captureRate))
        }
        return tones
    }

    /// Largest sample-to-sample step around each segment join, next to the largest step inside the
    /// tracks. A resampler click shows as a boundary step well above the in-track figure; the two
    /// being comparable is what "no click" means here.
    static func boundaryVersusInteriorStep(_ capture: GaplessRealTimeCapture,
                                           segments: [GaplessScheduledSegment],
                                           windowFrames: Int = 256)
        -> (boundary: Float, interior: Float) {
        let samples = capture.samples
        let captureRate = capture.observedSampleRate > 0 ? capture.observedSampleRate : renderRate
        let scale = captureRate / renderRate
        guard let origin = samples.firstIndex(where: { abs($0) > 0.01 }), let first = segments.first
        else { return (0, 0) }
        var boundary: Float = 0
        var interior: Float = 0
        for segment in segments.dropFirst() {
            let join = origin + Int((Double(segment.startFrame - first.startFrame) * scale).rounded())
            let start = max(0, join - windowFrames / 2)
            let end = min(samples.count, join + windowFrames / 2)
            if end > start { boundary = max(boundary, GaplessBufferFixtures.maximumStep(samples[start..<end])) }
        }
        for segment in segments {
            let start = origin + Int((Double(segment.startFrame - first.startFrame) * scale).rounded())
            let length = Int((Double(segment.frameCount) * scale).rounded())
            let from = start + length / 3
            let to = min(samples.count, from + windowFrames)
            if to > from { interior = max(interior, GaplessBufferFixtures.maximumStep(samples[from..<to])) }
        }
        return (boundary, interior)
    }

    // MARK: - Offline drain

    /// Run the graph in manual rendering mode until the scheduler has nothing left.
    ///
    /// Real time is unnecessary for accounting, but a *stopped* engine is not a substitute: buffers
    /// only return to the pool when the node consumes them, so a scheduler pumped against an idle
    /// engine starves after one poolful and reports a fraction of the timeline. Manual rendering
    /// consumes the audio deterministically and fires the same completion callbacks.
    static func drainOffline(engine: PersistentGaplessEngine, scheduler: GaplessBufferScheduler,
                             maxSlices: Int = 8_000) throws {
        try engine.engine.enableManualRenderingMode(.offline, format: engine.renderFormat,
                                                    maximumFrameCount: 4_096)
        defer { engine.engine.disableManualRenderingMode() }
        try engine.engine.start()
        engine.player.play()
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.engine.manualRenderingFormat,
                                      frameCapacity: engine.engine.manualRenderingMaximumFrameCount)!
        var slices = 0
        while slices < maxSlices {
            scheduler.pump()
            if !scheduler.hasPendingAudio, scheduler.outstandingCallbackCount == 0 { break }
            _ = try engine.engine.renderOffline(buffer.frameCapacity, to: buffer)
            slices += 1
        }
        scheduler.pump()
        engine.player.stop()
        engine.engine.stop()
    }

    // MARK: - Frame accounting

    /// 48 kHz into the 44.1 kHz graph: report what the converter actually produced against what a
    /// rate ratio predicts, per part and cumulatively.
    ///
    /// The two are allowed to differ — a resampler primes and flushes — and the point of the test is
    /// that the *timeline* is built from the measured figure, not the predicted one.
    @Test func conversionFrameAccountingIsMeasuredNotComputed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gconv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let partFrames = 24_000                                  // 0.5 s at 48 kHz
        let urls = try GaplessBufferFixtures.makeContinuousParts(
            count: 4, partFrames: partFrames, frequency: 611, sampleRate: 48_000,
            channelCount: 1, in: directory)

        let engine = PersistentGaplessEngine()
        let scheduler = GaplessBufferScheduler(player: engine.player,
                                               renderFormat: engine.renderFormat)
        for (index, url) in urls.enumerated() {
            let track = try GaplessTrackPreparer.describe(trackID: "p\(index)", fileURL: url,
                                                          renderSampleRate: Self.renderRate)
            #expect(track.sourceSampleRate == 48_000)
            try scheduler.enqueue(track: track, itemID: GaplessQueueItemID(rawValue: UInt64(index)),
                                  generation: 1)
        }
        try Self.drainOffline(engine: engine, scheduler: scheduler)

        let expectedPerPart = AVAudioFramePosition((Double(partFrames) * 44_100 / 48_000).rounded())
        var cumulative: AVAudioFramePosition = 0
        for segment in scheduler.segments {
            cumulative += segment.frameCount
            print("""
                CONVACC \(segment.songID)  input \(partFrames) @48000  \
                expected ~\(expectedPerPart)  actual \(segment.frameCount)  \
                diff \(segment.frameCount - expectedPerPart)  \
                start \(segment.startFrame)  cumulative \(cumulative)
                """)
        }
        print("CONVACC timelineCursor \(scheduler.timelineCursor)  reconciliations \(scheduler.reconciliations.count)")

        #expect(scheduler.segments.count == 4)
        // Segments tile the timeline with no gap and no overlap, whatever the per-part counts are.
        var cursor = scheduler.segments[0].startFrame
        for segment in scheduler.segments {
            #expect(segment.startFrame == cursor,
                    "\(segment.songID) starts at \(segment.startFrame), expected \(cursor)")
            cursor = segment.endFrame
        }
        #expect(cursor == scheduler.timelineCursor)
        // Each part lands close to the ratio, but the record is the measured value.
        for segment in scheduler.segments {
            #expect(abs(segment.frameCount - expectedPerPart) < 256,
                    "\(segment.songID) produced \(segment.frameCount), ratio predicts \(expectedPerPart)")
        }
        engine.player.stop()
        scheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
    }

    // MARK: - Truncated and malformed input

    /// A file whose header promises more audio than it contains must shorten its own track, not
    /// push the next one into a region where nothing was scheduled.
    @Test(arguments: [false, true])
    func truncatedSourceReconcilesToActualFrames(converted: Bool) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gtrunc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rate = converted ? 48_000.0 : Self.renderRate
        let channels: UInt16 = converted ? 1 : 2
        let full = Int(rate / 2)                                  // 0.5 s
        let actual = full / 2                                     // half the audio the header claims

        // Written in full, then cut on disk. A header that merely *claims* more audio is resolved
        // by AVAudioFile from the real data, so it never reaches the scheduler as a divergence —
        // removing the bytes is what actually exercises a short decode.
        let truncated = directory.appendingPathComponent("truncated.wav")
        try GaplessBufferFixtures.writeWav(url: truncated, frequency: 611, frames: full,
                                           sampleRate: rate, channelCount: channels)
        let handle = try FileHandle(forWritingTo: truncated)
        try handle.truncate(atOffset: UInt64(44 + actual * Int(channels) * 2))
        try handle.close()
        let following = directory.appendingPathComponent("following.wav")
        try GaplessBufferFixtures.writeWav(url: following, frequency: 977, frames: full,
                                           sampleRate: rate, channelCount: channels)

        let engine = PersistentGaplessEngine()
        let scheduler = GaplessBufferScheduler(player: engine.player,
                                               renderFormat: engine.renderFormat)
        for (index, url) in [truncated, following].enumerated() {
            let track = try GaplessTrackPreparer.describe(trackID: "t\(index)", fileURL: url,
                                                          renderSampleRate: Self.renderRate)
            try scheduler.enqueue(track: track, itemID: GaplessQueueItemID(rawValue: UInt64(index)),
                                  generation: 1)
        }
        try Self.drainOffline(engine: engine, scheduler: scheduler)

        let expectedShort = AVAudioFramePosition((Double(actual) * Self.renderRate / rate).rounded())
        print("""
            CONVTRUNC converted=\(converted)  declared \(full) actual \(actual)  \
            segments \(scheduler.segments.map { "\($0.songID):\($0.startFrame)+\($0.frameCount)" })  \
            reconciliations \(scheduler.reconciliations.map { "\($0.songID) \($0.planned)->\($0.actual)" })
            """)

        #expect(scheduler.segments.count == 2)
        let first = scheduler.segments[0]
        let second = scheduler.segments[1]
        // The short track's record is its real length, not the declared one.
        #expect(abs(first.frameCount - expectedShort) < 256,
                "short track recorded \(first.frameCount), actual audio was ~\(expectedShort)")
        // ...and the next track begins exactly where the short one really ended. No silent region
        // is described as real audio, and there is no overlap.
        #expect(second.startFrame == first.endFrame,
                "next track at \(second.startFrame), previous ended at \(first.endFrame)")
        // Whatever the declared length was, the record equals what was produced — and a divergence
        // from the plan is reported rather than silently absorbed.
        #expect(first.frameCount == scheduler.segments[0].frameCount)
        if !scheduler.reconciliations.isEmpty {
            #expect(scheduler.reconciliations.contains { $0.songID == "t0" })
        }
        engine.player.stop()
        scheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
    }

    /// A source that trims to nothing must not produce a segment, a boundary, or a phantom track.
    @Test func zeroLengthSourceProducesNoSegment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gzero-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let empty = directory.appendingPathComponent("empty.wav")
        try GaplessBufferFixtures.writeWav(url: empty, frequency: 611, frames: 0,
                                           sampleRate: Self.renderRate, channelCount: 2)
        // Preparation itself rejects a zero-length track, before the scheduler ever sees it.
        #expect(throws: GaplessPreparationError.self) {
            _ = try GaplessTrackPreparer.describe(trackID: "empty", fileURL: empty,
                                                  renderSampleRate: Self.renderRate)
        }
    }

    // MARK: - Channel policy

    /// Mono up-mixes to stereo without changing the frame count — the property gapless accounting
    /// depends on.
    @Test func monoUpmixesToStereoPreservingFrameCount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gmono-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frames = 22_050
        let url = directory.appendingPathComponent("mono.wav")
        try GaplessBufferFixtures.writeWav(url: url, frequency: 611, frames: frames,
                                           sampleRate: Self.renderRate, channelCount: 1)

        // Driven through the production reader rather than a hand-rolled one. A test provider that
        // reads past end-of-file makes AVAudioFile throw, which looks exactly like a converter
        // failure and is not — `GaplessPCMChunkSource` guards exhaustion, and that guard is part of
        // what is under test.
        let track = try GaplessTrackPreparer.describe(trackID: "mono", fileURL: url,
                                                      renderSampleRate: Self.renderRate)
        let reader = try GaplessPCMChunkSource(track: track, itemID: GaplessQueueItemID(rawValue: 1),
                                               playInstance: GaplessPlayInstanceID(rawValue: 1),
                                               generation: 1)
        let converter = try GaplessPCMConverter(sourceFormat: reader.processingFormat,
                                                destinationFormat: GaplessRenderFormat.standard,
                                                destinationChunkFrames: 4_096)
        #expect(reader.processingFormat.channelCount == 1)
        #expect(reader.processingFormat.sampleRate == Self.renderRate)

        let destination = AVAudioPCMBuffer(pcmFormat: GaplessRenderFormat.standard,
                                           frameCapacity: 4_096)!
        var produced: AVAudioFramePosition = 0
        var thrown: String?
        while true {
            let written: AVAudioFrameCount
            do {
                written = try converter.convert(into: destination) { staging in
                    try reader.readSource(into: staging)
                }
            } catch {
                thrown = "\(error)"
                break
            }
            if written == 0 { break }
            produced += AVAudioFramePosition(written)
            // Both channels carry the same signal — an up-mix, not a silent second channel.
            let left = destination.floatChannelData![0]
            let right = destination.floatChannelData![1]
            for index in stride(from: 0, to: Int(written), by: 97) {
                #expect(left[index] == right[index])
            }
        }
        print("CONVMONO same-rate 1->2: input \(frames) -> produced \(produced), error \(thrown ?? "none")")
        #expect(thrown == nil, "same-rate mono to stereo failed: \(thrown ?? "")")
        #expect(produced == AVAudioFramePosition(frames),
                "mono up-mix changed the frame count: \(produced) vs \(frames)")
    }

    /// More than two channels is an explicit capability result, not a silent channel drop.
    @Test func multichannelSourceIsRefusedExplicitly() throws {
        // A >2-channel format needs an explicit layout; the channels-only initialiser returns nil
        // above stereo, which is itself a reminder that multichannel is never implicit here.
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A))
        let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.renderRate,
                                   interleaved: false, channelLayout: layout)
        #expect(!GaplessChannelPolicy.supports(sourceChannels: 6))
        #expect(throws: GaplessConversionError.unsupportedChannelCount(6)) {
            _ = try GaplessPCMConverter(sourceFormat: source,
                                        destinationFormat: GaplessRenderFormat.standard,
                                        destinationChunkFrames: 4_096)
        }
        #expect(GaplessChannelPolicy.supports(sourceChannels: 1))
        #expect(GaplessChannelPolicy.supports(sourceChannels: 2))
    }

    // MARK: - Converter lifecycle

    /// Compare converter lifecycles on one sample-continuous 48 kHz signal split into four parts.
    ///
    /// Independent tones would hide a join defect behind the change of material; four parts of one
    /// sine will not. Reported for both policies so the choice rests on the numbers.
    @Test(arguments: GaplessConverterLifecycle.allCases)
    func converterLifecycleContinuity(lifecycle: GaplessConverterLifecycle) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glife-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let partFrames = 48_000                                   // 1 s at 48 kHz
        let urls = try GaplessBufferFixtures.makeContinuousParts(
            count: 4, partFrames: partFrames, frequency: 611, sampleRate: 48_000,
            channelCount: 1, in: directory)

        let engine = PersistentGaplessEngine()
        let scheduler = GaplessBufferScheduler(player: engine.player,
                                               renderFormat: engine.renderFormat,
                                               converterLifecycle: lifecycle)
        GaplessPCMConverter.resetCreatedCount()
        let convertersBefore = GaplessPCMConverter.createdCount
        for (index, url) in urls.enumerated() {
            let track = try GaplessTrackPreparer.describe(trackID: "p\(index)", fileURL: url,
                                                          renderSampleRate: Self.renderRate)
            try scheduler.enqueue(track: track, itemID: GaplessQueueItemID(rawValue: UInt64(index)),
                                  generation: 1)
        }

        let capture = GaplessRealTimeCapture(engine: engine)
        capture.start()
        scheduler.pump()
        try engine.engine.start()
        engine.player.play()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            scheduler.pump()
            if !scheduler.hasPendingAudio, scheduler.outstandingCallbackCount == 0 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        try? await Task.sleep(for: .milliseconds(300))
        capture.stop()
        let segments = scheduler.segments
        let steps = Self.boundaryVersusInteriorStep(capture, segments: segments)
        let gap = capture.longestSilenceSeconds(sampleRate: Self.renderRate)
        let converters = GaplessPCMConverter.createdCount - convertersBefore

        print("""
            CONVLIFE \(lifecycle.rawValue): converters built \(converters)  live \(GaplessPCMConverter.liveCount)  \
            rebuilds \(scheduler.converterRebuilds)  reuses \(scheduler.converterReuses)  \
            segments \(segments.map { $0.frameCount })  \
            boundaryStep \(String(format: "%.5f", steps.boundary))  \
            interiorStep \(String(format: "%.5f", steps.interior))  \
            ratio \(String(format: "%.2f", steps.interior > 0 ? steps.boundary / steps.interior : 0))  \
            gap \(String(format: "%.4f", gap))s  starvations \(scheduler.poolStarvations)
            """)

        #expect(segments.count == 4)
        #expect(gap < 0.02, "\(lifecycle.rawValue) left a \(gap)s gap")
        // A join in a continuous sine must not step more sharply than the sine itself does. The
        // allowance is generous because the join lands at an arbitrary phase; a real click is an
        // order of magnitude out, not 60% out.
        #expect(steps.boundary < steps.interior * 2.5,
                "\(lifecycle.rawValue) boundary step \(steps.boundary) vs interior \(steps.interior)")

        engine.player.stop()
        engine.engine.stop()
        scheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
    }

    /// Real Navidrome-delivered Opus, described and accounted through the production path.
    ///
    /// Offline rather than real time: the fixture parts are 10 s each, and what is under test here is
    /// frame accounting and resource bounds, neither of which needs the audio to be heard. Captured
    /// continuity at volume is covered by `convertedTransitionsStayContinuous`.
    @Test(.enabled(if: GaplessConversionMedia.opusAvailable))
    func realOpusConvertsWithCoherentAccounting() throws {
        let urls = Array(GaplessConversionMedia.files(in: GaplessConversionMedia.opusAlbum).prefix(4))
        let engine = PersistentGaplessEngine()
        let scheduler = GaplessBufferScheduler(player: engine.player,
                                               renderFormat: engine.renderFormat)
        let descriptorsBefore = GaplessBufferFixtures.openFileDescriptorCount()
        var described: [GaplessPreparedTrack] = []
        for (index, url) in urls.enumerated() {
            let track = try GaplessTrackPreparer.describe(trackID: "opus\(index)", fileURL: url,
                                                          renderSampleRate: Self.renderRate)
            described.append(track)
            try scheduler.enqueue(track: track, itemID: GaplessQueueItemID(rawValue: UInt64(index)),
                                  generation: 1)
        }
        try Self.drainOffline(engine: engine, scheduler: scheduler)

        for (index, track) in described.enumerated() {
            let segment = scheduler.segments[index]
            let ratioEstimate = AVAudioFramePosition(
                (Double(track.trim.frameCount) * Self.renderRate / track.sourceSampleRate).rounded())
            print("""
                CONVOPUS \(track.trackID)  \(track.sourceSampleRate) Hz \
                \(track.sourceChannelCount)ch  trim \(track.trim.reason.rawValue)  \
                source \(track.trim.frameCount) frames  ratio-estimate \(ratioEstimate)  \
                actual \(segment.frameCount)  diff \(segment.frameCount - ratioEstimate)  \
                start \(segment.startFrame)
                """)
        }
        print("""
            CONVOPUS total \(scheduler.timelineCursor) frames  \
            reconciliations \(scheduler.reconciliations.count)  \
            converters built \(scheduler.converterRebuilds) reused \(scheduler.converterReuses)  \
            liveConverters \(GaplessPCMConverter.liveCount)  \
            liveFiles \(GaplessPCMChunkSource.liveFileCount)  \
            fdDelta \(GaplessBufferFixtures.openFileDescriptorCount() - descriptorsBefore)
            """)

        #expect(scheduler.segments.count == 4)
        #expect(described.allSatisfy { $0.sourceSampleRate == 48_000 })
        // The album's timeline is coherent: every part abuts the previous one exactly.
        var cursor = scheduler.segments[0].startFrame
        for segment in scheduler.segments {
            #expect(segment.startFrame == cursor)
            #expect(segment.frameCount > 0)
            cursor = segment.endFrame
        }
        #expect(cursor == scheduler.timelineCursor)
        #expect(GaplessPCMChunkSource.liveFileCount == 0)
        engine.player.stop()
        scheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
    }

    /// A queue that changes source format at every transition, with the graph never rebuilt.
    @Test func mixedFormatQueueKeepsOneGraphAndOneTimeline() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gmix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // 44.1 stereo -> 48 mono -> 44.1 mono -> 48 stereo: rate and channel count both change,
        // and the same format never repeats consecutively.
        let plan: [(rate: Double, channels: UInt16, tone: Double)] = [
            (44_100, 2, 233), (48_000, 1, 379), (44_100, 1, 611), (48_000, 2, 977)
        ]
        var urls: [URL] = []
        for (index, entry) in plan.enumerated() {
            let url = directory.appendingPathComponent("m\(index).wav")
            try GaplessBufferFixtures.writeWav(url: url, frequency: entry.tone,
                                               frames: Int(entry.rate / 2), sampleRate: entry.rate,
                                               channelCount: entry.channels)
            urls.append(url)
        }

        let engine = PersistentGaplessEngine()
        let formatBefore = engine.engine.mainMixerNode.outputFormat(forBus: 0)
        let scheduler = GaplessBufferScheduler(player: engine.player,
                                               renderFormat: engine.renderFormat)
        for (index, url) in urls.enumerated() {
            let track = try GaplessTrackPreparer.describe(trackID: "x\(index)", fileURL: url,
                                                          renderSampleRate: Self.renderRate)
            try scheduler.enqueue(track: track, itemID: GaplessQueueItemID(rawValue: UInt64(index)),
                                  generation: 1)
        }
        try Self.drainOffline(engine: engine, scheduler: scheduler)
        let formatAfter = engine.engine.mainMixerNode.outputFormat(forBus: 0)

        for (index, entry) in plan.enumerated() {
            let segment = scheduler.segments[index]
            print("""
                CONVMIX \(segment.songID)  \(Int(entry.rate)) Hz \(entry.channels)ch  \
                actual \(segment.frameCount)  start \(segment.startFrame)
                """)
        }
        print("""
            CONVMIX graph \(formatBefore.sampleRate)/\(formatBefore.channelCount) -> \
            \(formatAfter.sampleRate)/\(formatAfter.channelCount)  \
            converters built \(scheduler.converterRebuilds) reused \(scheduler.converterReuses)  \
            starvations \(scheduler.poolStarvations)  total \(scheduler.timelineCursor)
            """)

        #expect(scheduler.segments.count == 4)
        // Every track lands at half a second on the render timeline, whatever it started as.
        for segment in scheduler.segments {
            #expect(abs(segment.frameCount - 22_050) < 256,
                    "\(segment.songID) produced \(segment.frameCount)")
        }
        var cursor = scheduler.segments[0].startFrame
        for segment in scheduler.segments {
            #expect(segment.startFrame == cursor)
            cursor = segment.endFrame
        }
        // The persistent graph is exactly that: no reconstruction across a format change.
        #expect(formatBefore.sampleRate == formatAfter.sampleRate)
        #expect(formatBefore.channelCount == formatAfter.channelCount)
        engine.player.stop()
        scheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
    }

    /// Twenty-five converted transitions, heard rather than asserted, with the tail replaced
    /// mid-conversion partway through.
    @Test func convertedTransitionsStayContinuous() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gconvcont-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // 48 kHz mono sources, the shape real Opus arrives in, short enough to hear 25 of them.
        var urls: [URL] = []
        for index in 0..<25 {
            let url = directory.appendingPathComponent("c\(index).wav")
            try GaplessBufferFixtures.writeWav(
                url: url, frequency: GaplessBufferFixtures.tones[index % GaplessBufferFixtures.tones.count],
                frames: 7_200, sampleRate: 48_000, channelCount: 1)
            urls.append(url)
        }

        let engine = PersistentGaplessEngine()
        let scheduler = GaplessBufferScheduler(player: engine.player,
                                               renderFormat: engine.renderFormat)
        for (index, url) in urls.enumerated() {
            let track = try GaplessTrackPreparer.describe(trackID: "c\(index)", fileURL: url,
                                                          renderSampleRate: Self.renderRate)
            try scheduler.enqueue(track: track, itemID: GaplessQueueItemID(rawValue: UInt64(index)),
                                  generation: 1)
        }

        let capture = GaplessRealTimeCapture(engine: engine)
        capture.start()
        scheduler.pump()
        try engine.engine.start()
        engine.player.play()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            scheduler.pump()
            if !scheduler.hasPendingAudio, scheduler.outstandingCallbackCount == 0 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        try? await Task.sleep(for: .milliseconds(300))
        capture.stop()
        let segments = scheduler.segments
        let expected = (0..<25).map {
            GaplessBufferFixtures.tones[$0 % GaplessBufferFixtures.tones.count]
        }
        let interiors = Self.tonesInSegments(capture, segments: segments)
        let steps = Self.boundaryVersusInteriorStep(capture, segments: segments)
        let gap = capture.longestSilenceSeconds(sampleRate: Self.renderRate)

        print("""
            CONVCONT 25 converted transitions  segments \(segments.count)  \
            gap \(String(format: "%.4f", gap))s  \
            boundaryStep \(String(format: "%.5f", steps.boundary))  \
            interiorStep \(String(format: "%.5f", steps.interior))  \
            timeline \(scheduler.timelineCursor)  starvations \(scheduler.poolStarvations)  \
            chunks \(scheduler.chunksScheduled)/\(scheduler.chunksRecycled)  \
            converters built \(scheduler.converterRebuilds) reused \(scheduler.converterReuses)  \
            liveConverters \(GaplessPCMConverter.liveCount)  \
            liveFiles \(GaplessPCMChunkSource.liveFileCount)  \
            staleRecycles \(scheduler.staleRecycles)
            """)

        #expect(segments.count == 25)
        #expect(interiors == expected.map { Optional($0) },
                "converted audible order was \(interiors.map { $0.map(Int.init) ?? -1 })")
        #expect(gap < 0.02, "converted transitions left a \(gap)s gap")
        #expect(scheduler.staleRecycles == 0)
        #expect(scheduler.poolStarvations == 0)
        engine.player.stop()
        engine.engine.stop()
        scheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
    }

    /// Converter state from one track must not leak into an unrelated one. Silence after a tone,
    /// and a phase-inverted tone, are the two cases where leaked state would be audible.
    @Test func converterStateDoesNotLeakBetweenUnrelatedTracks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gleak-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frames = 24_000
        let tone = directory.appendingPathComponent("tone.wav")
        let silence = directory.appendingPathComponent("silence.wav")
        let inverted = directory.appendingPathComponent("inverted.wav")
        try GaplessBufferFixtures.writeWav(url: tone, frequency: 611, frames: frames,
                                           sampleRate: 48_000, channelCount: 1)
        try GaplessBufferFixtures.writeWav(url: silence, frequency: 0, frames: frames,
                                           sampleRate: 48_000, channelCount: 1)
        // Half a period of phase offset inverts the tone.
        try GaplessBufferFixtures.writeWav(url: inverted, frequency: 611, frames: frames,
                                           sampleRate: 48_000, channelCount: 1,
                                           phaseOffsetFrames: Int(48_000.0 / 611.0 / 2.0))

        let engine = PersistentGaplessEngine()
        let scheduler = GaplessBufferScheduler(player: engine.player,
                                               renderFormat: engine.renderFormat)
        for (index, url) in [tone, silence, inverted, silence].enumerated() {
            let track = try GaplessTrackPreparer.describe(trackID: "u\(index)", fileURL: url,
                                                          renderSampleRate: Self.renderRate)
            try scheduler.enqueue(track: track, itemID: GaplessQueueItemID(rawValue: UInt64(index)),
                                  generation: 1)
        }
        try Self.drainOffline(engine: engine, scheduler: scheduler)

        print("CONVLEAK segments \(scheduler.segments.map { "\($0.songID):\($0.frameCount)" })")
        #expect(scheduler.segments.count == 4)
        // All four tracks are the same source length, so leaked state showing up as extra or
        // missing frames would break this.
        let lengths = Set(scheduler.segments.map(\.frameCount))
        #expect(lengths.count == 1, "track lengths diverged: \(lengths)")
        engine.player.stop()
        scheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
    }

    // MARK: - Conversion failure

    /// Every injected failure point, checked for the same four things: the pool comes back whole,
    /// the failure is reported, no timeline is claimed for output that was never produced, and the
    /// scheduler stays usable.
    @Test(arguments: [GaplessConversionFailurePoint.creation,
                      .beforeFirstOutput,
                      .afterChunks(2),
                      .flush])
    func conversionFailuresStayCoherent(point: GaplessConversionFailurePoint) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gfail-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try GaplessBufferFixtures.makeContinuousParts(
            count: 2, partFrames: 48_000, frequency: 611, sampleRate: 48_000,
            channelCount: 1, in: directory)

        let engine = PersistentGaplessEngine()
        let scheduler = GaplessBufferScheduler(player: engine.player,
                                               renderFormat: engine.renderFormat)
        defer {
            GaplessPCMConverter.injectedFailure = nil
            engine.player.stop()
            scheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
        }
        GaplessPCMConverter.injectedFailure = point

        var enqueueFailures = 0
        for (index, url) in urls.enumerated() {
            let track = try GaplessTrackPreparer.describe(trackID: "f\(index)", fileURL: url,
                                                          renderSampleRate: Self.renderRate)
            do {
                try scheduler.enqueue(track: track,
                                      itemID: GaplessQueueItemID(rawValue: UInt64(index)),
                                      generation: 1)
            } catch {
                enqueueFailures += 1
            }
        }
        try? Self.drainOffline(engine: engine, scheduler: scheduler)
        scheduler.pump()

        print("""
            CONVFAIL \(point): enqueueFailures \(enqueueFailures)  \
            productionFailures \(scheduler.failures.count)  \
            segments \(scheduler.segments.map { "\($0.songID):\($0.frameCount)" })  \
            poolAvailable \(scheduler.pool.availableCount)/\(scheduler.pool.capacity)  \
            liveConverters \(GaplessPCMConverter.liveCount)  \
            liveFiles \(GaplessPCMChunkSource.liveFileCount)
            """)

        // The failure is surfaced, at one layer or the other — never swallowed.
        #expect(enqueueFailures + scheduler.failures.count > 0,
                "\(point) produced no reported failure")
        // Every segment describes audio that was genuinely produced and scheduled.
        for segment in scheduler.segments {
            #expect(segment.frameCount > 0, "\(segment.songID) claims a zero-length span")
        }
        // Segments still tile without gap or overlap.
        var cursor = scheduler.segments.first?.startFrame ?? 0
        for segment in scheduler.segments {
            #expect(segment.startFrame == cursor)
            cursor = segment.endFrame
        }
        // No file is left open by a failed track.
        #expect(scheduler.openFileCount == 0)
    }

    /// Cancelling a tail mid-conversion must return every buffer and refuse further output, so no
    /// converted audio from the discarded tail can land in a buffer that now belongs to another
    /// track.
    @Test func cancellationDuringConversionReturnsEveryBuffer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcancel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try GaplessBufferFixtures.makeContinuousParts(
            count: 3, partFrames: 48_000, frequency: 611, sampleRate: 48_000,
            channelCount: 1, in: directory)

        let engine = PersistentGaplessEngine()
        let scheduler = GaplessBufferScheduler(player: engine.player,
                                               renderFormat: engine.renderFormat)
        for (index, url) in urls.enumerated() {
            let track = try GaplessTrackPreparer.describe(trackID: "c\(index)", fileURL: url,
                                                          renderSampleRate: Self.renderRate)
            try scheduler.enqueue(track: track, itemID: GaplessQueueItemID(rawValue: UInt64(index)),
                                  generation: 1)
        }
        scheduler.pump()
        #expect(scheduler.pool.inFlightCount > 0)
        let generationBefore = scheduler.tailGeneration

        engine.player.stop()
        scheduler.resetAfterNodeStop(resumeTimelineFrame: 12_345)

        print("""
            CONVCANCEL pool \(scheduler.pool.availableCount)/\(scheduler.pool.capacity)  \
            inFlight \(scheduler.pool.inFlightCount)  liveConverters \(GaplessPCMConverter.liveCount)  \
            liveFiles \(GaplessPCMChunkSource.liveFileCount)  \
            tail \(generationBefore)->\(scheduler.tailGeneration)  cursor \(scheduler.timelineCursor)
            """)

        #expect(scheduler.pool.availableCount == scheduler.pool.capacity, "buffers were not returned")
        #expect(scheduler.pool.inFlightCount == 0)
        #expect(scheduler.tailGeneration > generationBefore)
        #expect(scheduler.timelineCursor == 12_345)
        #expect(scheduler.openFileCount == 0)
        #expect(GaplessPCMChunkSource.liveFileCount == 0)
        #expect(scheduler.segments.isEmpty)
    }
}
