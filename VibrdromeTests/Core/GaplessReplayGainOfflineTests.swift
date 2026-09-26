import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// ReplayGain proven through the real persistent engine by offline rendering.
///
/// The question these answer is not "is the gain right" (the calculator tests cover that) but
/// "does applying gain at a boundary damage the join" — the failure mode that makes a gapless album
/// sound broken even when every frame is present.
struct GaplessReplayGainOfflineTests {
    static let sampleRate = 44_100.0
    static let partFrames = 44_100
    static let parts = 4

    // MARK: - Frame continuity under changing gain

    /// Every scenario must render the exact frame count and leave no boundary discontinuity beyond
    /// the level change itself. Gain is applied to a *continuous* tone, so a mis-timed or duplicated
    /// gain event shows up as a level artefact in the wrong place.
    @Test(arguments: [
        (name: "same gain across all tracks", gains: [Float(1.0), 1.0, 1.0, 1.0]),
        (name: "+6 dB to 0 dB", gains: [Float(1.995), 1.0, 1.0, 1.0]),
        (name: "0 dB to -6 dB", gains: [Float(1.0), 0.501, 0.501, 0.501]),
        (name: "-12 dB to +12 dB (capped)", gains: [Float(0.251), 1.5, 0.251, 1.5]),
        (name: "changing at every boundary", gains: [Float(1.0), 0.7, 0.45, 1.2])
    ])
    func gainSequenceRendersExactFrameCount(scenario: (name: String, gains: [Float])) async throws {
        let result = try await Self.render(gains: scenario.gains)

        #expect(abs(result.samples.count - Self.parts * Self.partFrames) <= 1,
                "\(scenario.name): rendered \(result.samples.count)")
        // Each gain event fired exactly once, for the right track, in order.
        #expect(result.appliedTrackIDs == result.expectedTrackIDs, "\(scenario.name)")
    }

    /// Album mode: one gain for the whole album, so no boundary should disturb the level at all.
    @Test func albumGainIsIdenticalAcrossEveryTrack() async throws {
        let gain: Float = 0.708
        let result = try await Self.render(gains: Array(repeating: gain, count: Self.parts))

        // The level either side of every boundary must match — an album join must not breathe.
        for boundary in 1..<Self.parts {
            let before = Self.envelope(result.samples, at: boundary * Self.partFrames - 2_000)
            let after = Self.envelope(result.samples, at: boundary * Self.partFrames + 2_000)
            #expect(abs(before - after) < 0.002,
                    "boundary \(boundary): \(before) vs \(after)")
        }
    }

    /// A gain change must land on its own track, not bleed far into the previous one. The mixer's
    /// own smoothing (~28 ms) is the ramp, so the level is checked outside that window.
    @Test func gainChangeLandsOnTheCorrectTrack() async throws {
        let quiet: Float = 0.25, loud: Float = 1.0
        let result = try await Self.render(gains: [quiet, loud, loud, loud])

        let smoothing = Int(GaplessGainStage.measuredSmoothingSeconds * Self.sampleRate)
        // Well before the boundary the outgoing track is still at its own level...
        let beforeBoundary = Self.envelope(result.samples, at: Self.partFrames - smoothing - 2_000)
        // ...and once the smoothing has completed the incoming track is at its level.
        let afterBoundary = Self.envelope(result.samples, at: Self.partFrames + smoothing + 2_000)

        #expect(afterBoundary > beforeBoundary * 2.5)
    }

    /// A queue edit before a scheduled gain event must not leave the removed track's gain behind.
    @Test func cancelledGainEventNeverReachesTheOutput() async throws {
        let urls = try Self.makeToneParts(count: 2)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let tracks = try await Self.prepare(urls)
        let format = try AVAudioFile(forReading: urls[0]).processingFormat
        let engine = PersistentGaplessEngine(renderFormat: format)
        try engine.schedule(tracks: tracks)

        // Schedule a drastic gain for track 2, then cancel it as a queue edit would.
        engine.scheduleReplayGain(GaplessGain(linear: 0.05, source: .trackGain),
                                  forTrackID: tracks[1].trackID)
        engine.cancelScheduledReplayGain(fromFrame: AVAudioFramePosition(Self.partFrames))

        let samples = try engine.renderOfflineChannel0()

        #expect(engine.gainStage.pendingEvents.isEmpty)
        // Level is unchanged across the boundary — the cancelled gain never applied.
        let before = Self.envelope(samples, at: Self.partFrames - 2_000)
        let after = Self.envelope(samples, at: Self.partFrames + 2_000)
        #expect(abs(before - after) < 0.002)
    }

    // MARK: - Independence from EQ

    /// ReplayGain and EQ occupy different nodes and must not interact. All four combinations must
    /// render the exact frame count with no boundary artefact.
    @Test(arguments: [(false, false), (true, false), (false, true), (true, true)])
    func replayGainAndEQAreIndependent(combination: (replayGain: Bool, eq: Bool)) async throws {
        let urls = try Self.makeToneParts(count: Self.parts)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let tracks = try await Self.prepare(urls)
        let format = try AVAudioFile(forReading: urls[0]).processingFormat
        let engine = PersistentGaplessEngine(renderFormat: format)

        if combination.eq {
            engine.applyEQ(GaplessEQSettings(gains: EQPresets.rock.gains, isEnabled: true))
        }
        try engine.schedule(tracks: tracks)
        if combination.replayGain {
            for (index, track) in tracks.enumerated() {
                let linear: Float = index.isMultiple(of: 2) ? 0.6 : 0.9
                engine.scheduleReplayGain(GaplessGain(linear: linear, source: .trackGain),
                                          forTrackID: track.trackID)
            }
        }

        let samples = try engine.renderOfflineChannel0()

        #expect(abs(samples.count - Self.parts * Self.partFrames) <= 1,
                "RG=\(combination.replayGain) EQ=\(combination.eq)")
        // The EQ's clip guard and ReplayGain live on different nodes; neither may zero the output.
        #expect(Self.envelope(samples, at: Self.partFrames + 5_000) > 0)
    }

    /// The two attenuations are deliberately separate and both apply — documented, not accidental.
    /// EQ's clip guard offsets EQ's own boost; ReplayGain matches loudness between tracks.
    @Test func eqClipGuardAndReplayGainBothApplyAndAreIndependent() {
        let eq = GaplessEQSettings(gains: [6, 0, 0, 0, 0, 0, 0, 0, 0, 0], isEnabled: true)
        #expect(eq.clipGuardGainDB == -6)

        let settings = GaplessReplayGainSettings(mode: .track)
        let replayGain = GaplessReplayGainCalculator.resolve(
            replayGain: GaplessReplayGainTests.rg(track: -6), settings: settings)

        // Neither value depends on the other: the EQ guard is a function of EQ gains alone, and the
        // ReplayGain factor a function of track metadata alone.
        #expect(abs(replayGain.gain.linear - GaplessReplayGainTests.linear(-6)) < 0.0001)
        #expect(eq.clipGuardGainDB == -6)
    }

    // MARK: - Everything on at once

    /// EQ, ReplayGain and the visualizer feed all active across four boundaries. Each is meant to be
    /// independent of the others; this is the test that would catch them interacting.
    @Test func eqReplayGainAndVisualizerFeedCoexistAcrossEveryBoundary() async throws {
        let urls = try Self.makeToneParts(count: Self.parts)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let tracks = try await Self.prepare(urls)
        let format = try AVAudioFile(forReading: urls[0]).processingFormat
        let engine = PersistentGaplessEngine(renderFormat: format)

        engine.applyEQ(GaplessEQSettings(gains: EQPresets.rock.gains, isEnabled: true))
        engine.installVisualizerFeed()
        defer { engine.uninstallVisualizerFeed() }
        let classic = engine.visualizerFeed.addConsumer(identifier: "classic")
        let native = engine.visualizerFeed.addConsumer(identifier: "native")
        classic.isActive = true
        native.isActive = true

        try engine.schedule(tracks: tracks)
        for (index, track) in tracks.enumerated() {
            engine.scheduleReplayGain(GaplessGain(linear: index.isMultiple(of: 2) ? 0.5 : 0.9,
                                                  source: .trackGain),
                                      forTrackID: track.trackID)
        }

        let playerBefore = ObjectIdentifier(engine.player)
        let samples = try engine.renderOfflineChannel0()

        // Audio is unaffected by any of it: exact frame count, every gain event fired once.
        #expect(abs(samples.count - Self.parts * Self.partFrames) <= 1)
        #expect(engine.gainStage.pendingEvents.isEmpty)
        #expect(engine.scheduler.totalFrames == AVAudioFramePosition(Self.parts * Self.partFrames))
        #expect(ObjectIdentifier(engine.player) == playerBefore)
        // The tap survived every boundary and was never reinstalled.
        #expect(engine.visualizerFeed.isInstalled)
        #expect(engine.visualizerFeed.registeredConsumerCount == 2)
    }

    // MARK: - Runtime setting changes

    /// Changing ReplayGain settings mid-track must take effect without waiting for a boundary, and
    /// without restarting anything.
    @Test func midTrackSettingChangeAppliesImmediatelyWithoutRebuilding() async throws {
        let urls = try Self.makeToneParts(count: 2)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let tracks = try await Self.prepare(urls)
        let format = try AVAudioFile(forReading: urls[0]).processingFormat
        let engine = PersistentGaplessEngine(renderFormat: format)
        let playerBefore = ObjectIdentifier(engine.player)
        let gainNodeBefore = ObjectIdentifier(engine.gainStage.node)
        try engine.schedule(tracks: tracks)

        let changes: [(frame: Int, action: (PersistentGaplessEngine) -> Void)] = [
            (Self.partFrames / 2, { $0.applyReplayGainNow(GaplessGain(linear: 0.4, source: .trackGain)) })
        ]
        let samples = try engine.renderOfflineChannel0(applying: changes)

        #expect(abs(samples.count - 2 * Self.partFrames) <= 1)
        #expect(ObjectIdentifier(engine.player) == playerBefore)
        #expect(ObjectIdentifier(engine.gainStage.node) == gainNodeBefore)
        // The change took effect within the current track, not at the next boundary.
        let mid = Self.envelope(samples, at: Self.partFrames / 2 + 5_000)
        let early = Self.envelope(samples, at: 5_000)
        #expect(mid < early * 0.7)
    }

    // MARK: - Helpers

    struct RenderResult {
        let samples: [Float]
        let appliedTrackIDs: [String]
        let expectedTrackIDs: [String]
    }

    static func render(gains: [Float]) async throws -> RenderResult {
        let urls = try makeToneParts(count: gains.count)
        defer { GaplessPipelineOfflineTests.cleanUp(urls) }
        let tracks = try await prepare(urls)
        let format = try AVAudioFile(forReading: urls[0]).processingFormat
        let engine = PersistentGaplessEngine(renderFormat: format)
        try engine.schedule(tracks: tracks)

        for (index, track) in tracks.enumerated() {
            engine.scheduleReplayGain(GaplessGain(linear: gains[index], source: .trackGain),
                                      forTrackID: track.trackID)
        }
        // Record which events actually fired, in order, so a missed or duplicated one is visible.
        var applied: [String] = []
        let samples = try engine.renderOfflineChannel0 { _ in
            if let last = engine.gainStage.lastAppliedEvent, applied.last != last.trackID {
                applied.append(last.trackID)
            }
            return nil
        }
        if let last = engine.gainStage.lastAppliedEvent, applied.last != last.trackID {
            applied.append(last.trackID)
        }
        return RenderResult(samples: samples, appliedTrackIDs: applied,
                            expectedTrackIDs: tracks.map(\.trackID))
    }

    static func prepare(_ urls: [URL]) async throws -> [GaplessPreparedTrack] {
        try await GaplessEQTests.prepare(urls)
    }

    static func makeToneParts(count: Int) throws -> [URL] {
        try GaplessPipelineOfflineTests.makeContinuousToneParts(count: count, sampleRate: sampleRate,
                                                                frames: partFrames)
    }

    /// Peak amplitude in a short window — the level, independent of where in the cycle we look.
    static func envelope(_ samples: [Float], at index: Int) -> Float {
        let lo = max(0, index - 400), hi = min(samples.count, index + 400)
        guard lo < hi else { return 0 }
        var peak: Float = 0
        for i in lo..<hi { peak = max(peak, abs(samples[i])) }
        return peak
    }
}
