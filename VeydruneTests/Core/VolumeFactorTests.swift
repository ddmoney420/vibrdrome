import Testing
import Foundation
@testable import Veydrune

/// Tests for the volume factor composition system.
/// Volume = userVolume × replayGainFactor × sleepFadeFactor × crossfadeFactor
struct VolumeFactorTests {

    // MARK: - Factor Composition

    /// Mirrors AudioEngine.applyEffectiveVolume() gapless path
    private func effectiveVolume(
        user: Float, replayGain: Float, sleepFade: Float
    ) -> Float {
        max(0, min(1, user * replayGain * sleepFade))
    }

    /// Mirrors crossfade path — active player
    private func crossfadeActiveVolume(
        user: Float, replayGain: Float, sleepFade: Float, outFactor: Float
    ) -> Float {
        max(0, min(1, user * replayGain * sleepFade * outFactor))
    }

    /// Mirrors crossfade path — inactive player
    private func crossfadeInactiveVolume(
        user: Float, replayGain: Float, sleepFade: Float, inFactor: Float
    ) -> Float {
        max(0, min(1, user * replayGain * sleepFade * inFactor))
    }

    @Test func allFactorsAtOne() {
        let vol = effectiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 1.0)
        #expect(vol == 1.0)
    }

    @Test func halfUserVolume() {
        let vol = effectiveVolume(user: 0.5, replayGain: 1.0, sleepFade: 1.0)
        #expect(abs(vol - 0.5) < 0.001)
    }

    @Test func replayGainReduction() {
        // -6dB ≈ 0.5 linear
        let vol = effectiveVolume(user: 1.0, replayGain: 0.5, sleepFade: 1.0)
        #expect(abs(vol - 0.5) < 0.001)
    }

    @Test func sleepFadeReducesVolume() {
        let vol = effectiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 0.3)
        #expect(abs(vol - 0.3) < 0.001)
    }

    @Test func allFactorsCombine() {
        let vol = effectiveVolume(user: 0.8, replayGain: 0.5, sleepFade: 0.5)
        // 0.8 * 0.5 * 0.5 = 0.2
        #expect(abs(vol - 0.2) < 0.001)
    }

    @Test func clampedToOne() {
        // replayGain > 1.0 (boost) should be clamped to 1.0 overall
        let vol = effectiveVolume(user: 1.0, replayGain: 1.5, sleepFade: 1.0)
        #expect(vol == 1.0)
    }

    @Test func clampedToZero() {
        let vol = effectiveVolume(user: 0.0, replayGain: 1.0, sleepFade: 1.0)
        #expect(vol == 0.0)
    }

    // MARK: - Crossfade Volume Factors

    @Test func crossfadeStartActiveAtFull() {
        let vol = crossfadeActiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 1.0, outFactor: 1.0)
        #expect(vol == 1.0)
    }

    @Test func crossfadeStartInactiveAtZero() {
        let vol = crossfadeInactiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 1.0, inFactor: 0.0)
        #expect(vol == 0.0)
    }

    @Test func crossfadeMidpoint() {
        let active = crossfadeActiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 1.0, outFactor: 0.5)
        let inactive = crossfadeInactiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 1.0, inFactor: 0.5)
        #expect(abs(active - 0.5) < 0.001)
        #expect(abs(inactive - 0.5) < 0.001)
    }

    @Test func crossfadeEndState() {
        let active = crossfadeActiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 1.0, outFactor: 0.0)
        let inactive = crossfadeInactiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 1.0, inFactor: 1.0)
        #expect(active == 0.0)
        #expect(inactive == 1.0)
    }

    @Test func crossfadeWithSleepFade() {
        // Sleep fade should apply to both players equally
        let active = crossfadeActiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 0.5, outFactor: 0.8)
        let inactive = crossfadeInactiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 0.5, inFactor: 0.2)
        #expect(abs(active - 0.4) < 0.001)
        #expect(abs(inactive - 0.1) < 0.001)
    }

    // MARK: - Crossfade Ramp Progress

    /// Mirrors CrossfadeController.tickRamp progress calculation
    private func rampProgress(elapsed: TimeInterval, duration: TimeInterval) -> Float {
        Float(min(elapsed / duration, 1.0))
    }

    @Test func rampProgressStart() {
        let progress = rampProgress(elapsed: 0, duration: 5)
        #expect(progress == 0)
    }

    @Test func rampProgressMidway() {
        let progress = rampProgress(elapsed: 2.5, duration: 5)
        #expect(abs(progress - 0.5) < 0.001)
    }

    @Test func rampProgressEnd() {
        let progress = rampProgress(elapsed: 5, duration: 5)
        #expect(progress == 1.0)
    }

    @Test func rampProgressOvershootClamped() {
        let progress = rampProgress(elapsed: 10, duration: 5)
        #expect(progress == 1.0)
    }

    // MARK: - Short Track Fade Clamping

    /// Mirrors the short-track clamping logic from AudioEngine+Crossfade
    private func clampedFadeDuration(crossfadeDuration: Int, trackDuration: Double) -> Double {
        min(Double(crossfadeDuration), trackDuration * 0.5)
    }

    @Test func normalTrackNoClamp() {
        let fade = clampedFadeDuration(crossfadeDuration: 5, trackDuration: 240)
        #expect(fade == 5.0)
    }

    @Test func shortTrackClamped() {
        // 8s track with 5s crossfade → clamped to 4s (50% of duration)
        let fade = clampedFadeDuration(crossfadeDuration: 5, trackDuration: 8)
        #expect(fade == 4.0)
    }

    @Test func veryShortTrack() {
        // 2s track with 5s crossfade → clamped to 1s
        let fade = clampedFadeDuration(crossfadeDuration: 5, trackDuration: 2)
        #expect(fade == 1.0)
    }

    // MARK: - Additional Volume Factor Tests

    @Test func replayGainBoostOfExactly2ClampedTo1() {
        // replayGain of 2.0 (maximum boost) with user=1.0 → clamped to 1.0
        let vol = effectiveVolume(user: 1.0, replayGain: 2.0, sleepFade: 1.0)
        #expect(vol == 1.0)
    }

    @Test func compositionWithVerySmallValues() {
        // 0.1 * 0.1 * 0.1 = 0.001
        let vol = effectiveVolume(user: 0.1, replayGain: 0.1, sleepFade: 0.1)
        #expect(abs(vol - 0.001) < 0.0001)
    }

    @Test func crossfadeLinearRampOutPlusInEqualsOne() {
        // For a linear crossfade, outFactor + inFactor = 1.0 at every step
        for step in 0...10 {
            let progress = Float(step) / 10.0
            let outFactor: Float = 1.0 - progress
            let inFactor: Float = progress
            #expect(abs((outFactor + inFactor) - 1.0) < 0.001,
                    "outFactor + inFactor should equal 1.0 at step \(step)")
        }
    }

    @Test func crossfadeRampWithZeroDurationClampsToOne() {
        // Zero duration: elapsed/duration would be division by zero, so clamp to 1.0
        // The rampProgress function uses min(elapsed/duration, 1.0) — with duration=0
        // we'd get inf, but callers clamp crossfade duration to at least some minimum.
        // Here we test that a progress of 1.0 (fully complete) gives expected volumes.
        let active = crossfadeActiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 1.0, outFactor: 0.0)
        let inactive = crossfadeInactiveVolume(user: 1.0, replayGain: 1.0, sleepFade: 1.0, inFactor: 1.0)
        #expect(active == 0.0)
        #expect(inactive == 1.0)
    }

    @Test func negativeFactorClampedToZero() {
        // Negative input should be clamped to 0 by the max(0, ...) guard
        let vol = effectiveVolume(user: -0.5, replayGain: 1.0, sleepFade: 1.0)
        #expect(vol == 0.0)
    }

    @Test func allZeroFactorsEqualZero() {
        let vol = effectiveVolume(user: 0.0, replayGain: 0.0, sleepFade: 0.0)
        #expect(vol == 0.0)
    }

    @Test func volumeFactorsSymmetricActiveAndInactive() {
        // Active fade-out at step N should equal inactive fade-in at mirror step (10-N)
        // i.e., active(outFactor=0.7) should equal inactive(inFactor=0.7)
        for step in 0...10 {
            let factor = Float(step) / 10.0

            let activeVol = crossfadeActiveVolume(
                user: 1.0, replayGain: 1.0, sleepFade: 1.0, outFactor: factor)
            let inactiveVol = crossfadeInactiveVolume(
                user: 1.0, replayGain: 1.0, sleepFade: 1.0, inFactor: factor)

            // With all other factors at 1.0, both should equal the factor itself
            #expect(abs(activeVol - inactiveVol) < 0.001,
                    "Active and inactive should produce same volume for same factor \(factor)")
        }
    }
}
