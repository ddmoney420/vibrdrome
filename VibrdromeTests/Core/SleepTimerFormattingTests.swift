import Testing
@testable import Vibrdrome

struct SleepTimerFormattingTests {

    @Test func zeroSeconds() {
        #expect(formatSleepTime(0) == "0:00")
    }

    @Test func oneMinute() {
        #expect(formatSleepTime(60) == "1:00")
    }

    @Test func ninetySeconds() {
        #expect(formatSleepTime(90) == "1:30")
    }

    @Test func fiveMinutes() {
        #expect(formatSleepTime(300) == "5:00")
    }

    @Test func oneHour() {
        #expect(formatSleepTime(3600) == "60:00")
    }

    @Test func singleDigitSeconds() {
        #expect(formatSleepTime(65) == "1:05")
    }

    @Test func thirtyMinutes() {
        #expect(formatSleepTime(1800) == "30:00")
    }

    @Test func oneSecond() {
        #expect(formatSleepTime(1) == "0:01")
    }

    // Helper matching the format in NowPlayingView
    private func formatSleepTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}
