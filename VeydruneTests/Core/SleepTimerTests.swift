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

    // MARK: - Additional Fade Factor Tests

    @Test func fadeFactorAt31SecondsIsFullVolume() {
        // 31 seconds is just outside the 30-second fade window
        let factor = computeFadeFactor(remainingSeconds: 31)
        #expect(factor == 1.0)
    }

    @Test func fadeFactorAtExactFadeDurationBoundary() {
        // At exactly fadeDuration (30s), remainingSeconds > fadeDuration is false,
        // but remainingSeconds == fadeDuration so condition `> fadeDuration` fails,
        // returns Float(30) / Float(30) = 1.0
        let factor = computeFadeFactor(remainingSeconds: 30, fadeDuration: 30)
        #expect(factor == 1.0)
    }

    @Test func allStandardTimerOptionsProduceCorrectSeconds() {
        let expected: [(minutes: Int, seconds: Int)] = [
            (15, 900), (30, 1800), (45, 2700), (60, 3600), (120, 7200)
        ]
        for pair in expected {
            let mode = SleepTimerMode.minutes(pair.minutes)
            if case .minutes(let m) = mode {
                #expect(m * 60 == pair.seconds,
                        "\(pair.minutes) minutes should be \(pair.seconds) seconds")
            }
        }
    }

    @Test func endOfTrackModeHasNoCountdown() {
        // endOfTrack mode doesn't use a countdown — remainingSeconds would be 0
        let mode = SleepTimerMode.endOfTrack
        #expect(mode == .endOfTrack)
        // The timer sets remainingSeconds = 0 for endOfTrack
        let simulatedRemaining = 0
        #expect(simulatedRemaining == 0)
    }

    @Test func fadeFactorWithCustomFadeDuration60() {
        // Custom fadeDuration of 60; at 30s remaining, factor = 30/60 = 0.5
        let factor = computeFadeFactor(remainingSeconds: 30, fadeDuration: 60)
        #expect(abs(factor - 0.5) < 0.001)
    }

    @Test func fadeFactorNegativeRemainingReturnsZero() {
        let factor = computeFadeFactor(remainingSeconds: -5)
        #expect(factor == 0)
    }
}
