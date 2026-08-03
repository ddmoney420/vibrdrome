import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// ReplayGain policy tests.
///
/// The first job is *parity*: the new calculator must reproduce
/// `AudioEngine.computeReplayGainFactor(for:)` exactly, so moving onto the persistent engine does
/// not change anyone's playback levels. The second is the behaviour the old path never had — peak
/// protection, explicit diagnostics, and gain changes bound to the audible boundary.
struct GaplessReplayGainTests {

    static func rg(track: Double? = nil, album: Double? = nil,
                   trackPeak: Double? = nil, albumPeak: Double? = nil) -> ReplayGain {
        ReplayGain(trackGain: track, albumGain: album, trackPeak: trackPeak,
                   albumPeak: albumPeak, baseGain: nil)
    }

    static func linear(_ db: Double) -> Float { Float(pow(10, db / 20)) }

    // MARK: - Parity with the existing engine

    @Test func modeOffAlwaysYieldsUnity() {
        let result = GaplessReplayGainCalculator.resolve(
            replayGain: Self.rg(track: -9, album: -7), settings: .off)

        #expect(result.gain.linear == 1.0)
        #expect(result.diagnostics.fallbackReason == .modeOff)
    }

    @Test func trackModeUsesTrackGain() {
        let settings = GaplessReplayGainSettings(mode: .track)
        let result = GaplessReplayGainCalculator.resolve(
            replayGain: Self.rg(track: -6, album: -3), settings: settings)

        #expect(abs(result.gain.linear - Self.linear(-6)) < 0.0001)
        #expect(result.diagnostics.selectedGainDB == -6)
        #expect(result.gain.source == .trackGain)
    }

    @Test func albumModeUsesAlbumGain() {
        let settings = GaplessReplayGainSettings(mode: .album)
        let result = GaplessReplayGainCalculator.resolve(
            replayGain: Self.rg(track: -6, album: -3), settings: settings)

        #expect(abs(result.gain.linear - Self.linear(-3)) < 0.0001)
        #expect(result.diagnostics.selectedGainDB == -3)
        #expect(result.gain.source == .albumGain)
    }

    /// Existing behaviour: album mode falls back to the track value when there is no album value.
    @Test func albumModeFallsBackToTrackGain() {
        let settings = GaplessReplayGainSettings(mode: .album)
        let result = GaplessReplayGainCalculator.resolve(replayGain: Self.rg(track: -6), settings: settings)

        #expect(abs(result.gain.linear - Self.linear(-6)) < 0.0001)
        #expect(result.gain.source == .trackGain)
        #expect(result.diagnostics.fallbackReason == nil)
    }

    @Test func preampIsAddedToTheSelectedGain() {
        let settings = GaplessReplayGainSettings(mode: .track, preampDB: 3)
        let result = GaplessReplayGainCalculator.resolve(replayGain: Self.rg(track: -6), settings: settings)

        #expect(abs(result.gain.linear - Self.linear(-3)) < 0.0001)
        #expect(result.diagnostics.preampDB == 3)
    }

    @Test func gainIsCappedAtTheProjectCeiling() {
        let settings = GaplessReplayGainSettings(mode: .track, preampDB: 6)
        let result = GaplessReplayGainCalculator.resolve(replayGain: Self.rg(track: 12), settings: settings)

        #expect(result.gain.linear == GaplessReplayGainSettings.defaultMaximumLinear)
    }

    @Test func missingReplayGainDataUsesTheFallback() {
        let settings = GaplessReplayGainSettings(mode: .track, fallbackDB: -6)
        let result = GaplessReplayGainCalculator.resolve(replayGain: nil, settings: settings)

        #expect(abs(result.gain.linear - Self.linear(-6)) < 0.0001)
        #expect(result.diagnostics.fallbackReason == .noReplayGainData)
    }

    /// A fallback of 0 dB means "do nothing", not "apply 0 dB as a measured value".
    @Test func zeroFallbackLeavesUntaggedTracksAtUnity() {
        let settings = GaplessReplayGainSettings(mode: .track, fallbackDB: 0)
        let result = GaplessReplayGainCalculator.resolve(replayGain: nil, settings: settings)

        #expect(result.gain.linear == 1.0)
        #expect(result.gain.source == .noMetadata)
    }

    @Test func presentMetadataWithNoUsableFieldUsesTheFallback() {
        let settings = GaplessReplayGainSettings(mode: .track, fallbackDB: -4)
        let result = GaplessReplayGainCalculator.resolve(replayGain: Self.rg(album: -8), settings: settings)

        #expect(abs(result.gain.linear - Self.linear(-4)) < 0.0001)
        #expect(result.diagnostics.fallbackReason == .selectedGainMissing)
    }

    // MARK: - Invalid values

    /// Server metadata is not guaranteed sane, and NaN reaching `pow` would poison the mixer.
    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func invalidGainValuesFallBackInsteadOfPropagating(bad: Double) {
        let settings = GaplessReplayGainSettings(mode: .track, fallbackDB: -6)
        let result = GaplessReplayGainCalculator.resolve(replayGain: Self.rg(track: bad), settings: settings)

        #expect(result.gain.linear.isFinite)
        #expect(abs(result.gain.linear - Self.linear(-6)) < 0.0001)
        #expect(result.diagnostics.fallbackReason == .selectedGainInvalid)
    }

    @Test(arguments: [Double.nan, 0, -0.5, .infinity])
    func invalidPeaksAreIgnoredRatherThanTrusted(badPeak: Double) {
        let settings = GaplessReplayGainSettings(mode: .track, clippingPreventionEnabled: true)
        let result = GaplessReplayGainCalculator.resolve(
            replayGain: Self.rg(track: 6, trackPeak: badPeak), settings: settings)

        #expect(result.gain.linear.isFinite)
        #expect(result.diagnostics.rawPeak == nil)
        #expect(result.diagnostics.clippingAdjustmentDB == 0)
    }

    // MARK: - Peak protection

    /// Off by default, because the existing app never reads the peak fields — enabling it silently
    /// would change playback levels.
    @Test func peakProtectionIsOffByDefault() {
        // +3 dB stays under the project's 1.5x ceiling, so the only thing that could reduce it here
        // is peak protection — which must not engage by default.
        let settings = GaplessReplayGainSettings(mode: .track)
        let result = GaplessReplayGainCalculator.resolve(
            replayGain: Self.rg(track: 3, trackPeak: 0.99), settings: settings)

        #expect(abs(result.gain.linear - Self.linear(3)) < 0.0001)
        #expect(result.diagnostics.clippingAdjustmentDB == 0)

        // With it enabled the same track is held down to 1/peak.
        let guarded = GaplessReplayGainCalculator.resolve(
            replayGain: Self.rg(track: 3, trackPeak: 0.99),
            settings: GaplessReplayGainSettings(mode: .track, clippingPreventionEnabled: true))
        #expect(abs(guarded.gain.linear - Float(1.0 / 0.99)) < 0.0001)
    }

    @Test func peakProtectionHoldsTheLoudestSampleBelowFullScale() {
        let settings = GaplessReplayGainSettings(mode: .track, clippingPreventionEnabled: true)
        let result = GaplessReplayGainCalculator.resolve(
            replayGain: Self.rg(track: 6, trackPeak: 0.9), settings: settings)

        // linearGain * peak <= 1.0
        #expect(Double(result.gain.linear) * 0.9 <= 1.0001)
        #expect(abs(result.gain.linear - Float(1.0 / 0.9)) < 0.0001)
        #expect(result.diagnostics.clippingAdjustmentDB < 0)
        #expect(result.diagnostics.rawPeak == 0.9)
    }

    /// Peak protection only ever reduces gain — a quiet track is not boosted to fill headroom.
    @Test func peakProtectionNeverIncreasesGain() {
        let settings = GaplessReplayGainSettings(mode: .track, clippingPreventionEnabled: true)
        let result = GaplessReplayGainCalculator.resolve(
            replayGain: Self.rg(track: -12, trackPeak: 0.1), settings: settings)

        #expect(abs(result.gain.linear - Self.linear(-12)) < 0.0001)
        #expect(result.diagnostics.clippingAdjustmentDB == 0)
    }

    @Test func albumModeUsesAlbumPeak() {
        let settings = GaplessReplayGainSettings(mode: .album, clippingPreventionEnabled: true)
        let result = GaplessReplayGainCalculator.resolve(
            replayGain: Self.rg(track: 6, album: 6, trackPeak: 0.5, albumPeak: 0.95), settings: settings)

        #expect(result.diagnostics.rawPeak == 0.95)
    }

    // MARK: - Diagnostics

    @Test func diagnosticsCarryEveryInputAndTheResult() {
        let settings = GaplessReplayGainSettings(mode: .album, preampDB: 2,
                                                 clippingPreventionEnabled: true)
        let result = GaplessReplayGainCalculator.resolve(
            replayGain: Self.rg(track: -8, album: -5, trackPeak: 0.8, albumPeak: 0.98), settings: settings)

        let diagnostics = result.diagnostics
        #expect(diagnostics.mode == .album)
        #expect(diagnostics.rawTrackGainDB == -8)
        #expect(diagnostics.rawAlbumGainDB == -5)
        #expect(diagnostics.selectedGainDB == -5)
        #expect(diagnostics.preampDB == 2)
        #expect(diagnostics.rawPeak == 0.98)
        #expect(diagnostics.finalLinearGain == result.gain.linear)
        #expect(abs(diagnostics.finalGainDB - Double(20 * log10(result.gain.linear))) < 0.001)
    }

    // MARK: - Boundary-aligned application

    @Test func gainAppliesAtTheBoundaryFrameNotBefore() {
        let stage = GaplessGainStage()
        let gain = GaplessGain(linear: 0.5, source: .trackGain)
        stage.schedule(GaplessGainEvent(trackID: "t2", boundaryFrame: 44_100, gain: gain))

        #expect(stage.advance(toRenderFrame: 44_099) == nil)
        #expect(stage.currentGain == .unity)
        #expect(stage.node.outputVolume == 1.0)

        let applied = stage.advance(toRenderFrame: 44_100)
        #expect(applied?.trackID == "t2")
        #expect(stage.currentGain == gain)
        #expect(stage.node.outputVolume == 0.5)
    }

    @Test func anAppliedEventIsNeverAppliedTwice() {
        let stage = GaplessGainStage()
        stage.schedule(GaplessGainEvent(trackID: "t2", boundaryFrame: 100,
                                        gain: GaplessGain(linear: 0.5, source: .trackGain)))

        #expect(stage.advance(toRenderFrame: 200)?.trackID == "t2")
        #expect(stage.advance(toRenderFrame: 300) == nil)
        #expect(stage.pendingEvents.isEmpty)
    }

    /// Album playback: every track shares one gain, so no boundary should disturb the level at all.
    @Test func identicalGainAcrossAnAlbumNeverRetriggersTheNode() {
        let stage = GaplessGainStage()
        let gain = GaplessGain(linear: 0.708, source: .albumGain)
        for (index, id) in ["t1", "t2", "t3", "t4"].enumerated() {
            stage.schedule(GaplessGainEvent(trackID: id,
                                            boundaryFrame: AVAudioFramePosition(index * 44_100),
                                            gain: gain))
        }

        stage.advance(toRenderFrame: 0)
        let volumeAfterFirst = stage.node.outputVolume
        for boundary in 1...3 {
            stage.advance(toRenderFrame: AVAudioFramePosition(boundary * 44_100))
            // Unchanged gain must not restart the node's smoothing — that is what keeps an
            // album-gain join completely untouched.
            #expect(stage.node.outputVolume == volumeAfterFirst)
        }
    }

    @Test func rescheduleForTheSameTrackReplacesRatherThanDuplicates() {
        let stage = GaplessGainStage()
        stage.schedule(GaplessGainEvent(trackID: "t2", boundaryFrame: 100,
                                        gain: GaplessGain(linear: 0.5, source: .trackGain)))
        stage.schedule(GaplessGainEvent(trackID: "t2", boundaryFrame: 100,
                                        gain: GaplessGain(linear: 0.25, source: .trackGain)))

        #expect(stage.pendingEvents.count == 1)
        stage.advance(toRenderFrame: 100)
        #expect(stage.currentGain.linear == 0.25)
    }

    // MARK: - Queue mutation safety

    @Test func cancellingFromAFrameDropsEventsForAudioThatWillNotPlay() {
        let stage = GaplessGainStage()
        for (index, id) in ["t1", "t2", "t3"].enumerated() {
            stage.schedule(GaplessGainEvent(trackID: id,
                                            boundaryFrame: AVAudioFramePosition(index * 1_000),
                                            gain: GaplessGain(linear: Float(index + 1) * 0.2,
                                                              source: .trackGain)))
        }

        stage.cancelEvents(fromFrame: 1_000)

        #expect(stage.pendingEvents.map(\.trackID) == ["t1"])
    }

    @Test func cancellingOneTrackLeavesTheRest() {
        let stage = GaplessGainStage()
        for (index, id) in ["t1", "t2", "t3"].enumerated() {
            stage.schedule(GaplessGainEvent(trackID: id,
                                            boundaryFrame: AVAudioFramePosition(index * 1_000),
                                            gain: .unity))
        }

        stage.cancelEvent(forTrackID: "t2")

        #expect(stage.pendingEvents.map(\.trackID) == ["t1", "t3"])
    }

    /// A removed track's gain must never be applied to whatever ends up at its frame.
    @Test func replacedQueueDoesNotApplyStaleGain() {
        let stage = GaplessGainStage()
        stage.schedule(GaplessGainEvent(trackID: "removed", boundaryFrame: 1_000,
                                        gain: GaplessGain(linear: 0.1, source: .trackGain)))

        stage.cancelAllPendingEvents()
        stage.schedule(GaplessGainEvent(trackID: "replacement", boundaryFrame: 1_000,
                                        gain: GaplessGain(linear: 0.9, source: .trackGain)))
        stage.advance(toRenderFrame: 1_000)

        #expect(stage.currentGain.linear == 0.9)
        #expect(stage.lastAppliedEvent?.trackID == "replacement")
    }

    @Test func resetClearsGainAndEveryPendingEvent() {
        let stage = GaplessGainStage()
        stage.schedule(GaplessGainEvent(trackID: "t2", boundaryFrame: 10,
                                        gain: GaplessGain(linear: 0.3, source: .trackGain)))
        stage.advance(toRenderFrame: 10)

        stage.reset()

        #expect(stage.currentGain == .unity)
        #expect(stage.node.outputVolume == 1.0)
        #expect(stage.pendingEvents.isEmpty)
        #expect(stage.lastAppliedEvent == nil)
    }

    /// A skip lands the listener mid-queue; only the events at or after the new position survive.
    @Test func manualSkipKeepsOnlyEventsAheadOfTheNewPosition() {
        let stage = GaplessGainStage()
        for (index, id) in ["t1", "t2", "t3", "t4"].enumerated() {
            stage.schedule(GaplessGainEvent(trackID: id,
                                            boundaryFrame: AVAudioFramePosition(index * 1_000),
                                            gain: GaplessGain(linear: 0.5, source: .trackGain)))
        }

        // User skips to t3: everything from t2's boundary onward is re-planned.
        stage.cancelEvents(fromFrame: 1_000)
        stage.schedule(GaplessGainEvent(trackID: "t3", boundaryFrame: 1_000,
                                        gain: GaplessGain(linear: 0.7, source: .trackGain)))

        #expect(stage.pendingEvents.map(\.trackID) == ["t1", "t3"])
        stage.advance(toRenderFrame: 1_000)
        #expect(stage.currentGain.linear == 0.7)
    }
}
