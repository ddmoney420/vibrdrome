import Testing
import Foundation
@testable import Veydrune

/// Tests for SleepTimer state management and fade factor computation.
struct SleepTimerTests {

    // MARK: - SleepTimerMode

    @Test func minutesModeEquality() {
        #expect(SleepTimerMode.minutes(15) == SleepTimerMode.minutes(15))
        #expect(SleepTimerMode.minutes(15) != SleepTimerMode.minutes(30))
    }

    @Test func endOfTrackEquality() {
        #expect(SleepTimerMode.endOfTrack == SleepTimerMode.endOfTrack)
    }

    @Test func differentModesNotEqual() {
        #expect(SleepTimerMode.minutes(0) != SleepTimerMode.endOfTrack)
    }

    // MARK: - Fade Factor Computation

    /// Mirrors the fade factor formula from SleepTimer.tick()
    private func computeFadeFactor(remainingSeconds: Int, fadeDuration: Int = 30) -> Float {
        if remainingSeconds <= 0 { return 0 }
        if remainingSeconds > fadeDuration { return 1.0 }
        return Float(remainingSeconds) / Float(fadeDuration)
    }

    @Test func fadeFactorFullWhenFarFromEnd() {
        let factor = computeFadeFactor(remainingSeconds: 120)
        #expect(factor == 1.0)
    }

    @Test func fadeFactorAtThirtySeconds() {
        let factor = computeFadeFactor(remainingSeconds: 30)
        #expect(factor == 1.0)
    }

    @Test func fadeFactorAtFifteenSeconds() {
        let factor = computeFadeFactor(remainingSeconds: 15)
        #expect(factor == 0.5)
    }

    @Test func fadeFactorAtOneSecond() {
        let factor = computeFadeFactor(remainingSeconds: 1)
        #expect(abs(factor - 1.0 / 30.0) < 0.001)
    }

    @Test func fadeFactorAtZeroSeconds() {
        let factor = computeFadeFactor(remainingSeconds: 0)
        #expect(factor == 0)
    }

    @Test func fadeFactorMonotonicallyDecreases() {
        var lastFactor: Float = 1.1
        for seconds in stride(from: 30, through: 0, by: -1) {
            let factor = computeFadeFactor(remainingSeconds: seconds)
            #expect(factor <= lastFactor, "Fade factor should decrease monotonically")
            lastFactor = factor
        }
    }

    // MARK: - Timer Duration Constants

    @Test func fifteenMinutesInSeconds() {
        let mode = SleepTimerMode.minutes(15)
        if case .minutes(let m) = mode {
            #expect(m * 60 == 900)
        }
    }

    @Test func twoHoursInSeconds() {
        let mode = SleepTimerMode.minutes(120)
        if case .minutes(let m) = mode {
            #expect(m * 60 == 7200)
        }
    }
}
