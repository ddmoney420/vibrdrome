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
}
