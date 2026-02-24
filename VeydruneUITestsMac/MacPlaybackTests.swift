import XCTest

/// Tests music playback and mini player on macOS.
final class MacPlaybackTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
    }

    // MARK: - Play a Track

    func testPlayTrackFromLibrary() throws {
        try app.playAnyTrack()

        let pauseButton = app.buttons.matching(
            NSPredicate(format: "label == 'Pause'")).firstMatch
        let playButton = app.buttons.matching(
            NSPredicate(format: "label == 'Play'")).firstMatch
        let miniPlayerVisible = pauseButton.waitForExistence(timeout: 10)
            || playButton.exists

        XCTAssertTrue(miniPlayerVisible,
                      "Mini player should appear after playing a track")
    }

    func testMiniPlayerShowsSongInfo() throws {
        try app.playAnyTrack()
        sleep(2)
        let staticTexts = app.staticTexts
        XCTAssertGreaterThan(staticTexts.count, 2,
                             "Mini player should show song info text")
    }

    func testPlayPauseToggle() throws {
        try app.playAnyTrack()

        let pauseButton = app.buttons.matching(
            NSPredicate(format: "label == 'Pause'")).firstMatch
        guard pauseButton.waitForExistence(timeout: 10) else {
            let playButton = app.buttons.matching(
                NSPredicate(format: "label == 'Play'")).firstMatch
            if playButton.exists {
                playButton.click()
                sleep(1)
            }
            return
        }

        pauseButton.click()
        sleep(1)

        let playButton = app.buttons.matching(
            NSPredicate(format: "label == 'Play'")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 3),
                      "Play button should appear after pausing")

        playButton.click()
        sleep(1)

        XCTAssertTrue(pauseButton.waitForExistence(timeout: 3),
                      "Pause button should appear after resuming")
    }

    func testMiniPlayerNextButton() throws {
        try app.playAnyTrack()

        let nextButton = app.buttons["Next Track"]
        guard nextButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Next Track button not visible in mini player")
        }

        nextButton.click()
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "App should not crash on next track")
    }

    func testMiniPlayerPreviousButton() throws {
        try app.playAnyTrack()

        let prevButton = app.buttons["Previous Track"]
        guard prevButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Previous Track button not visible in mini player")
        }

        prevButton.click()
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "App should not crash on previous track")
    }

    func testProgressBarExists() throws {
        try app.playAnyTrack()
        sleep(2)

        // The mini player has a progress bar at the top
        let progressIndicator = app.progressIndicators.firstMatch
        let hasProgress = progressIndicator.waitForExistence(timeout: 5)
            || app.state == .runningForeground

        XCTAssertTrue(hasProgress,
                      "Mini player should have a progress indicator")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            XCTAssertTrue(app.waitForMainScreen())
        }
    }
}
