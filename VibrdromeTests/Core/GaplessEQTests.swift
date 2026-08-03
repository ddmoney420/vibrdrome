import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Objective tests for the persistent EQ stage.
///
/// Two things are being proven, and they are different:
/// 1. **Mapping** — the `AVAudioUnitEQ` reproduces the existing `EQTapProcessor` semantics exactly,
///    so no user-visible EQ behaviour changes.
/// 2. **Independence** — EQ state and gapless scheduling do not interact. Enabling, disabling, or
///    adjusting EQ must not restart the engine, rebuild the graph, or alter a single scheduled frame.
struct GaplessEQTests {
    static let sampleRate = 44_100.0
    static let partFrames = 44_100
    static let freq = 220.0
    static let amp: Float = 0.4

    // MARK: - Mapping existing EQ settings

    @Test func bandsMatchTheExistingTenBandLayout() {
        let stage = GaplessEQStage()

        #expect(stage.node.bands.count == EQPresets.frequencies.count)
        for (index, frequency) in EQPresets.frequencies.enumerated() {
            #expect(stage.node.bands[index].frequency == frequency)
            // EQTapProcessor uses the RBJ peaking shape at a fixed 1-octave bandwidth.
            #expect(stage.node.bands[index].bandwidth == 1.0)
            #expect(stage.node.bands[index].filterType == .parametric)
        }
    }

    @Test func gainsAreClampedToTheExistingTwelveDecibelLimit() {
        let stage = GaplessEQStage()

        stage.apply(GaplessEQSettings(gains: [99, -99, 6, 0, 0, 0, 0, 0, 0, 0], isEnabled: true))

        #expect(stage.effectiveGain(forBand: 0) == 12)
        #expect(stage.effectiveGain(forBand: 1) == -12)
        #expect(stage.effectiveGain(forBand: 2) == 6)
    }

    /// `EQTapProcessor` attenuates the input by the largest positive band gain so boost cannot clip.
    /// The same protection has to survive the move onto `AVAudioUnitEQ`.
    @Test func clipGuardMatchesTheExistingPreGainRule() {
        let boosted = GaplessEQSettings(gains: [6, 3, 0, 0, 0, 0, 0, 0, 0, 0], isEnabled: true)
        #expect(boosted.clipGuardGainDB == -6)

        // Below 0.5 dB of boost the existing code applies no attenuation, and neither do we.
        let tiny = GaplessEQSettings(gains: [0.2, 0, 0, 0, 0, 0, 0, 0, 0, 0], isEnabled: true)
        #expect(tiny.clipGuardGainDB == 0)

        // Cuts only: nothing can clip, so no attenuation.
        let cuts = GaplessEQSettings(gains: [-6, -3, 0, 0, 0, 0, 0, 0, 0, 0], isEnabled: true)
        #expect(cuts.clipGuardGainDB == 0)
    }

    @Test func clipGuardIsAppliedToTheNodeOnlyWhileEnabled() {
        let stage = GaplessEQStage()
        let settings = GaplessEQSettings(gains: [6, 0, 0, 0, 0, 0, 0, 0, 0, 0], isEnabled: true)

        stage.apply(settings)
        #expect(stage.node.globalGain == -6)
        #expect(!stage.node.bypass)

        stage.setEnabled(false, sampleRate: Self.sampleRate)
        Self.settleRamp(stage)
        #expect(stage.node.bypass)
        // Bypassed means transparent: no residual attenuation left behind.
        #expect(stage.node.globalGain == 0)
    }

    // MARK: - Ramping

    /// Disabling must not engage bypass until the bands have reached flat *and* the filters have
    /// drained — otherwise the switch itself is the discontinuity the ramp exists to prevent.
    @Test func bypassEngagesOnlyAfterTheRampAndTheSettlePeriod() {
        let stage = GaplessEQStage()
        stage.apply(GaplessEQSettings(gains: [10, 0, 0, 0, 0, 0, 0, 0, 0, 0], isEnabled: true))

        stage.setEnabled(false, sampleRate: Self.sampleRate)

        #expect(stage.isRamping)
        #expect(!stage.node.bypass)              // still processing while it ramps down
        stage.advanceRamp(byFrames: 16)
        #expect(!stage.node.bypass)
        #expect(abs(stage.effectiveGain(forBand: 0)) < 10)   // already moving toward flat

        // Ramp finished: bands are flat, but the filters still hold energy, so bypass must wait.
        while stage.isRamping { stage.advanceRamp(byFrames: GaplessEQStage.rampUpdateFrames) }
        #expect(stage.effectiveGain(forBand: 0) == 0)
        #expect(stage.isSettlingBeforeBypass)
        #expect(!stage.node.bypass)

        Self.settleRamp(stage)
        #expect(!stage.isTransitioning)
        #expect(stage.node.bypass)               // engaged only now, when it is a no-op
    }

    /// Re-enabling during the settle period must cancel it — bypass was never engaged, so there is
    /// nothing to switch and nothing that can click.
    @Test func reEnablingDuringSettleCancelsTheBypass() {
        let stage = GaplessEQStage()
        stage.apply(GaplessEQSettings(gains: [8, 0, 0, 0, 0, 0, 0, 0, 0, 0], isEnabled: true))
        stage.setEnabled(false, sampleRate: Self.sampleRate)
        while stage.isRamping { stage.advanceRamp(byFrames: GaplessEQStage.rampUpdateFrames) }
        #expect(stage.isSettlingBeforeBypass)

        stage.setEnabled(true, sampleRate: Self.sampleRate)
        Self.settleRamp(stage)

        #expect(!stage.node.bypass)
        #expect(!stage.isSettlingBeforeBypass)
        #expect(stage.effectiveGain(forBand: 0) == 8)
    }

    /// Enabling drops bypass immediately — at that instant the bands are flat, so the node is
    /// transparent and the switch is inaudible — then ramps up to the user's curve.
    @Test func enablingLeavesBypassImmediatelyButRampsGainsUp() {
        let stage = GaplessEQStage()
        stage.apply(GaplessEQSettings(gains: [10, 0, 0, 0, 0, 0, 0, 0, 0, 0], isEnabled: false))
        #expect(stage.node.bypass)

        stage.setEnabled(true, sampleRate: Self.sampleRate)

        #expect(!stage.node.bypass)                          // transparent at this instant
        #expect(stage.effectiveGain(forBand: 0) == 0)        // flat, so nothing changed audibly
        Self.settleRamp(stage)
        #expect(stage.effectiveGain(forBand: 0) == 10)       // settles on the user's curve
        #expect(stage.node.globalGain == -10)                // clip guard restored
    }

    @Test func rampSettlesExactlyOnTheRequestedValues() {
        let stage = GaplessEQStage()
        let target = GaplessEQSettings(gains: EQPresets.jazz.gains, isEnabled: true)

        stage.beginTransition(to: target, sampleRate: Self.sampleRate)
        Self.settleRamp(stage)

        for (index, gain) in EQPresets.jazz.gains.enumerated() {
            #expect(stage.effectiveGain(forBand: index) == gain)
        }
        #expect(!stage.isRamping)
    }

    /// A transition to the state already in effect should not start a pointless ramp.
    @Test func transitionToTheCurrentStateIsANoOp() {
        let stage = GaplessEQStage()
        let settings = GaplessEQSettings(gains: [3, 0, 0, 0, 0, 0, 0, 0, 0, 0], isEnabled: true)
        stage.apply(settings)

        stage.beginTransition(to: settings, sampleRate: Self.sampleRate)

        #expect(!stage.isRamping)
    }

    /// Advance a transition (ramp + settle) to completion the way the render loop would.
    static func settleRamp(_ stage: GaplessEQStage) {
        var guardCount = 0
        while stage.isTransitioning && guardCount < 100_000 {
            stage.advanceRamp(byFrames: GaplessEQStage.rampUpdateFrames)
            guardCount += 1
        }
    }

    @Test func disabledEQIsBypassedRatherThanFlattened() {
        let stage = GaplessEQStage()

        stage.apply(GaplessEQSettings(gains: [6, 6, 6, 0, 0, 0, 0, 0, 0, 0], isEnabled: false))

        #expect(stage.node.bypass)
        // The node runs flat so that engaging bypass is acoustically a no-op, but the user's gains
        // are retained in the settings and come back on re-enable.
        #expect(stage.effectiveGain(forBand: 0) == 0)
        #expect(stage.settings.gains[0] == 6)
    }

    @Test func singleBandChangeLeavesOtherBandsAlone() {
        let stage = GaplessEQStage()
        stage.apply(GaplessEQSettings(gains: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], isEnabled: true))

        stage.setGain(-4, forBand: 3, sampleRate: Self.sampleRate)
        Self.settleRamp(stage)

        #expect(stage.effectiveGain(forBand: 3) == -4)
        #expect(stage.effectiveGain(forBand: 2) == 3)
        #expect(stage.effectiveGain(forBand: 4) == 5)
        #expect(!stage.node.bypass)
    }

    @Test func everyBuiltInPresetMapsWithinTheAllowedRange() {
        let stage = GaplessEQStage()

        for preset in EQPresets.all {
            stage.apply(GaplessEQSettings(gains: preset.gains, isEnabled: true))
            for index in preset.gains.indices {
                let gain = stage.effectiveGain(forBand: index)
                #expect(gain >= -GaplessEQSettings.gainLimitDB)
                #expect(gain <= GaplessEQSettings.gainLimitDB)
            }
        }
    }

    // MARK: - Graph identity: EQ never rebuilds anything

    /// The whole architecture rests on this: the nodes present at the end of a session of EQ
    /// activity are the *same objects* that were there at the start.
    @Test func eqActivityNeverReplacesGraphNodes() throws {
        let engine = PersistentGaplessEngine()
        let playerBefore = ObjectIdentifier(engine.player)
        let eqBefore = ObjectIdentifier(engine.eq)
        let mixerBefore = ObjectIdentifier(engine.outputMixer)
        let gainBefore = ObjectIdentifier(engine.gainStage.node)

        engine.setEQEnabled(true)
        engine.setEQGain(8, forBand: 0)
        engine.setEQGain(-5, forBand: 9)
        engine.setEQEnabled(false)
        engine.setEQEnabled(true)

        #expect(ObjectIdentifier(engine.player) == playerBefore)
        #expect(ObjectIdentifier(engine.eq) == eqBefore)
        #expect(ObjectIdentifier(engine.outputMixer) == mixerBefore)
        #expect(ObjectIdentifier(engine.gainStage.node) == gainBefore)
    }

    // MARK: - Scheduling is independent of EQ state

    /// Same queue, opposite EQ states — the scheduled frame ranges must be byte-for-byte identical.
    /// If EQ could shift a boundary by even one frame, metadata and scrobble timing would drift.
    @Test func scheduledFrameRangesAreIdenticalWithEQOnAndOff() async throws {
        let urls = try Self.makeToneParts(count: 4)
        defer { Self.cleanUp(urls) }
        let tracks = try await Self.prepare(urls)

        func segments(eqEnabled: Bool) throws -> [GaplessScheduler.Segment] {
            let format = try AVAudioFile(forReading: urls[0]).processingFormat
            let engine = PersistentGaplessEngine(renderFormat: format)
            engine.applyEQ(GaplessEQSettings(gains: [8, 4, 0, 0, 0, 0, 0, 0, 0, -6],
                                             isEnabled: eqEnabled))
            try engine.schedule(tracks: tracks)
            return engine.scheduler.segments
        }

        #expect(try segments(eqEnabled: false) == segments(eqEnabled: true))
    }

    /// Toggling EQ *after* audio is scheduled must not disturb what was scheduled.
    @Test func togglingEQAfterSchedulingDoesNotChangeTheSchedule() async throws {
        let urls = try Self.makeToneParts(count: 3)
        defer { Self.cleanUp(urls) }
        let tracks = try await Self.prepare(urls)
        let format = try AVAudioFile(forReading: urls[0]).processingFormat
        let engine = PersistentGaplessEngine(renderFormat: format)
        try engine.schedule(tracks: tracks)
        let before = engine.scheduler.segments

        engine.setEQEnabled(true)
        engine.setEQGain(10, forBand: 5)
        engine.setEQEnabled(false)

        #expect(engine.scheduler.segments == before)
        #expect(engine.scheduler.totalFrames == AVAudioFramePosition(3 * Self.partFrames))
    }

    // MARK: - Frame continuity under each EQ state

    @Test func bypassedEQRendersFrameContinuous() async throws {
        let result = try await Self.renderAlbum(eq: .bypassed)

        #expect(result.frameCountExact)
        #expect(result.worstDelta <= result.inCycleDelta * 3.0)
        for delta in result.boundaryDeltas { #expect(delta <= result.inCycleDelta * 3.0) }
    }

    /// The node is live and processing, just with every band at 0 dB. A peaking biquad at 0 dB gain
    /// is mathematically unity, so this must be as continuous as bypass — and it proves that running
    /// the filter chain does not itself disturb the joins.
    @Test func activeNeutralEQRendersFrameContinuous() async throws {
        let neutral = GaplessEQSettings(gains: Array(repeating: 0, count: 10), isEnabled: true)
        let result = try await Self.renderAlbum(eq: neutral)

        #expect(result.frameCountExact)
        #expect(result.worstDelta <= result.inCycleDelta * 3.0)
        for delta in result.boundaryDeltas { #expect(delta <= result.inCycleDelta * 3.0) }
    }

    /// With an audible curve the output legitimately differs from the source, so comparing samples
    /// to the unprocessed tone would be meaningless. What must still hold is *structural*: the exact
    /// frame count, and no boundary that stands out from the filtered signal's own local behaviour.
    @Test func audibleEQKeepsBoundariesIndistinguishableFromTheFilteredSignal() async throws {
        let preset = GaplessEQSettings(gains: EQPresets.rock.gains, isEnabled: true)
        let result = try await Self.renderAlbum(eq: preset)

        // No inserted, missing, or duplicated output region.
        #expect(result.frameCountExact)
        // Each boundary is judged against the *filtered* signal's in-cycle step, not the source's.
        for delta in result.boundaryDeltas {
            #expect(delta <= result.inCycleDelta * 3.0)
        }
        #expect(result.worstDelta <= result.inCycleDelta * 3.0)
    }

    // MARK: - Runtime changes mid-render

    /// Enable, adjust, disable and re-enable EQ *while audio is rendering*, including a band change
    /// immediately before a track boundary. Nothing may restart, and no change may leave a step
    /// discontinuity in the output.
    @Test func midRenderEQChangesProduceNoDiscontinuity() async throws {
        let urls = try Self.makeToneParts(count: 4)
        defer { Self.cleanUp(urls) }
        let tracks = try await Self.prepare(urls)
        let format = try AVAudioFile(forReading: urls[0]).processingFormat
        let engine = PersistentGaplessEngine(renderFormat: format)
        try engine.schedule(tracks: tracks)

        // Changes land mid-track and just before boundaries (each part is `partFrames` long).
        let boundary = Self.partFrames
        let changes: [(frame: Int, action: (PersistentGaplessEngine) -> Void)] = [
            (boundary / 2, { $0.setEQEnabled(true) }),                       // enable mid-track
            (boundary - 2_000, { $0.setEQGain(9, forBand: 1) }),             // band change pre-boundary
            (boundary + boundary / 2, { $0.setEQGain(-9, forBand: 7) }),     // more bands
            (2 * boundary - 1_000, { $0.setEQEnabled(false) }),              // disable pre-boundary
            (3 * boundary - 1_000, { $0.setEQEnabled(true) })                // re-enable pre-boundary
        ]

        let rendered = try engine.renderOfflineChannel0(applying: changes)

        #expect(engine.engine.isRunning == false)   // stopped only by the render finishing
        #expect(abs(rendered.count - 4 * Self.partFrames) <= 1)

        let measurement = Self.measure(rendered, partFrames: Self.partFrames, parts: 4)
        // A bypass flip or band jump that stepped the waveform would show as a delta spike far
        // above the signal's own in-cycle step.
        #expect(measurement.worstDelta <= measurement.inCycleDelta * 3.0,
                """
                worst delta \(measurement.worstDelta) at frame \(measurement.worstIndex) \
                vs in-cycle \(measurement.inCycleDelta); \
                change frames \(changes.map(\.frame)); boundaries \
                \([boundary, 2 * boundary, 3 * boundary])
                """)
        for delta in measurement.boundaryDeltas {
            #expect(delta <= measurement.inCycleDelta * 3.0)
        }
    }

    // MARK: - Helpers

    struct Result {
        let frameCountExact: Bool
        let inCycleDelta: Float
        let worstDelta: Float
        let boundaryDeltas: [Float]
    }

    static func renderAlbum(eq: GaplessEQSettings, parts: Int = 4) async throws -> Result {
        let urls = try makeToneParts(count: parts)
        defer { cleanUp(urls) }
        let tracks = try await prepare(urls)
        let format = try AVAudioFile(forReading: urls[0]).processingFormat
        let engine = PersistentGaplessEngine(renderFormat: format)
        engine.applyEQ(eq)
        try engine.schedule(tracks: tracks)
        let rendered = try engine.renderOfflineChannel0()
        let measurement = measure(rendered, partFrames: partFrames, parts: parts)
        return Result(frameCountExact: abs(rendered.count - parts * partFrames) <= 1,
                      inCycleDelta: measurement.inCycleDelta,
                      worstDelta: measurement.worstDelta,
                      boundaryDeltas: measurement.boundaryDeltas)
    }

    static func prepare(_ urls: [URL]) async throws -> [GaplessPreparedTrack] {
        let format = try AVAudioFile(forReading: urls[0]).processingFormat
        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(albumFiles: urls),
                                            renderSampleRate: format.sampleRate)
        var tracks: [GaplessPreparedTrack] = []
        for url in urls { tracks.append(try await preparer.preparedTrack(url.lastPathComponent)) }
        return tracks
    }

    struct Measurement {
        let inCycleDelta: Float
        let worstDelta: Float
        let worstIndex: Int
        let boundaryDeltas: [Float]
    }

    static func measure(_ rendered: [Float], partFrames: Int, parts: Int) -> Measurement {
        var peak: Float = 0
        for value in rendered.prefix(partFrames) { peak = max(peak, abs(value)) }
        let start = rendered.firstIndex { abs($0) > peak * 0.05 } ?? 0
        let tone = Array(rendered[start...])

        var inCycle: Float = 0
        for i in 5_000..<6_000 where i + 1 < tone.count {
            inCycle = max(inCycle, abs(tone[i + 1] - tone[i]))
        }
        var worst: Float = 0
        var worstIndex = 0
        for i in 0..<max(0, tone.count - 1) {
            let delta = abs(tone[i + 1] - tone[i])
            if delta > worst { worst = delta; worstIndex = i }
        }

        var boundaries: [Float] = []
        for boundary in 1..<parts {
            let idx = boundary * partFrames
            guard idx > 0, idx < tone.count else { continue }
            boundaries.append(abs(tone[idx] - tone[idx - 1]))
        }
        return Measurement(inCycleDelta: inCycle, worstDelta: worst, worstIndex: worstIndex,
                           boundaryDeltas: boundaries)
    }

    static func makeToneParts(count: Int) throws -> [URL] {
        try GaplessPipelineOfflineTests.makeContinuousToneParts(count: count, sampleRate: sampleRate,
                                                               frames: partFrames)
    }

    static func cleanUp(_ urls: [URL]) { GaplessPipelineOfflineTests.cleanUp(urls) }
}
