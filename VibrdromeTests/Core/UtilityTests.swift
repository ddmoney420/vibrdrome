import Testing
import Foundation
@testable import Vibrdrome

struct FormatDurationTests {

    // MARK: - formatDuration(Int)

    @Test func zeroSeconds() {
        #expect(formatDuration(0) == "0:00")
    }

    @Test func singleDigitSeconds() {
        #expect(formatDuration(5) == "0:05")
    }

    @Test func oneMinute() {
        #expect(formatDuration(60) == "1:00")
    }

    @Test func minutesAndSeconds() {
        #expect(formatDuration(185) == "3:05")
    }

    @Test func exactHour() {
        #expect(formatDuration(3600) == "1:00:00")
    }

    @Test func hoursMinutesSeconds() {
        #expect(formatDuration(3661) == "1:01:01")
    }

    @Test func largeValue() {
        #expect(formatDuration(36000) == "10:00:00")
    }

    @Test func justUnderHour() {
        #expect(formatDuration(3599) == "59:59")
    }

    // MARK: - formatDuration(TimeInterval)

    @Test func timeIntervalZero() {
        #expect(formatDuration(TimeInterval(0)) == "0:00")
    }

    @Test func timeIntervalWithDecimals() {
        #expect(formatDuration(TimeInterval(65.7)) == "1:05")
    }

    @Test func timeIntervalNegative() {
        // Negative values produce unexpected output — documents current behavior
        // (callers clamp to 0 before calling)
        #expect(formatDuration(TimeInterval(-5)) == "0:-5")
    }

    // MARK: - Additional Duration Format Tests

    @Test func ninetySeconds() {
        #expect(formatDuration(90) == "1:30")
    }

    @Test func nineMinutesFiftyNineSeconds() {
        #expect(formatDuration(599) == "9:59")
    }

    @Test func twoHoursOneMinuteOneSecond() {
        #expect(formatDuration(7261) == "2:01:01")
    }

    @Test func timeIntervalJustUnderHour() {
        // 3599.9 truncated to Int = 3599 → "59:59"
        #expect(formatDuration(TimeInterval(3599.9)) == "59:59")
    }
}

struct StringSanitizedTests {

    @Test func normalString() {
        #expect("hello world".sanitizedFileName == "hello world")
    }

    @Test func forwardSlash() {
        #expect("AC/DC".sanitizedFileName == "AC_DC")
    }

    @Test func backslash() {
        #expect("path\\to".sanitizedFileName == "path_to")
    }

    @Test func multipleIllegalChars() {
        #expect("file:name?test".sanitizedFileName == "file_name_test")
    }

    @Test func allIllegalChars() {
        #expect("/\\?%*|\"<>:".sanitizedFileName == "__________")
    }

    @Test func leadingTrailingWhitespace() {
        #expect("  hello  ".sanitizedFileName == "hello")
    }

    @Test func emptyString() {
        #expect("".sanitizedFileName == "")
    }

    @Test func unicodePreserved() {
        #expect("café résumé".sanitizedFileName == "café résumé")
    }

    @Test func mixedContent() {
        #expect("Artist: The Best of <Greatest Hits>".sanitizedFileName == "Artist_ The Best of _Greatest Hits_")
    }

    // MARK: - Additional String Sanitization Tests

    @Test func dotFilePreserved() {
        #expect(".hidden".sanitizedFileName == ".hidden")
    }

    @Test func veryLongFilenamePreserved() {
        let longName = String(repeating: "a", count: 120)
        #expect(longName.sanitizedFileName == longName)
    }

    @Test func japaneseCJKCharactersPreserved() {
        #expect("日本語テスト".sanitizedFileName == "日本語テスト")
    }

    @Test func consecutiveIllegalCharsReplaced() {
        // Each illegal char is replaced individually
        #expect("a//b".sanitizedFileName == "a__b")
    }
}

struct ErrorPresenterTests {

    @Test func subsonicAuthError() {
        let error = SubsonicError.apiError(code: 40, message: "Wrong username or password.")
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg == "Wrong username or password.")
    }

    @Test func subsonicNotFound() {
        let error = SubsonicError.apiError(code: 70, message: "Data not found.")
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg == "The requested item was not found.")
    }

    @Test func subsonicPermission() {
        let error = SubsonicError.apiError(code: 50, message: "")
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg == "You don't have permission for this action.")
    }

    @Test func httpUnauthorized() {
        let error = SubsonicError.httpError(401)
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg.contains("Authentication"))
    }

    @Test func httpServerError() {
        let error = SubsonicError.httpError(500)
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg.contains("server"))
    }

    @Test func noServerConfigured() {
        let error = SubsonicError.noServerConfigured
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg.contains("server"))
    }

    @Test func networkUnavailable() {
        let error = SubsonicError.networkUnavailable
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg.contains("network") || msg.contains("connection"))
    }

    @Test func invalidURL() {
        let error = SubsonicError.invalidURL
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg.contains("URL") || msg.contains("address"))
    }

    @Test func urlErrorTimeout() {
        let error = URLError(.timedOut)
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg.contains("timed out"))
    }

    @Test func urlErrorNoInternet() {
        let error = URLError(.notConnectedToInternet)
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg.lowercased().contains("internet") || msg.lowercased().contains("connection"))
    }

    @Test func unknownError() {
        struct CustomError: Error {}
        let msg = ErrorPresenter.userMessage(for: CustomError())
        #expect(msg.contains("try again"))
    }

    // MARK: - Additional HTTP Error Tests

    @Test func httpForbiddenMentionsPermission() {
        let error = SubsonicError.httpError(403)
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg.lowercased().contains("permission") || msg.lowercased().contains("denied"),
                "403 message should mention permission or denied, got: \(msg)")
    }

    @Test func httpNotFoundMentionsNotFound() {
        let error = SubsonicError.httpError(404)
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(msg.lowercased().contains("not found"),
                "404 message should mention not found, got: \(msg)")
    }

    @Test func apiErrorCode60TrialExpiredHasMessage() {
        let error = SubsonicError.apiError(code: 60, message: "")
        let msg = ErrorPresenter.userMessage(for: error)
        #expect(!msg.isEmpty, "Trial expired error should have a non-empty message")
        #expect(msg.lowercased().contains("trial") || msg.lowercased().contains("expired"),
                "Code 60 message should mention trial or expired, got: \(msg)")
    }
}
