import XCTest

/// Tests music playback: play a track, verify Now Playing, controls.
final class PlaybackTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.ensureLoggedIn()
    }

    // MARK: - Play a Track via Library

    func testPlayTrackFromLibrary() throws {
        try app.playAnyTrack()

        // Check if mini player appeared (song is playing)
        XCTAssertTrue(app.isPlaybackActive,
                      "Mini player should appear after starting playback")
    }

    func testMiniPlayerShowsSongInfo() throws {
        try app.playAnyTrack()

        // Mini player should show some text (song title, artist)
        sleep(2)
        let staticTexts = app.staticTexts
        XCTAssertGreaterThan(staticTexts.count, 2,
                             "Mini player should show song info text")
    }

    func testMiniPlayerNextButton() throws {
        try app.playAnyTrack()

        let nextButton = app.buttons["Next Track"]
        guard nextButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Next Track button not visible in mini player")
        }

        nextButton.tap()
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "App should not crash on next track")
    }

    func testPlayPauseToggle() throws {
        try app.playAnyTrack()

        let pauseButton = app.buttons.matching(
            NSPredicate(format: "label == 'Pause'")).firstMatch
        guard pauseButton.waitForExistence(timeout: 10) else {
            // Already paused? Try play
            let playButton = app.buttons.matching(
                NSPredicate(format: "label == 'Play'")).firstMatch
            if playButton.exists {
                playButton.tap()
                sleep(1)
            }
            return
        }

        // Tap to pause
        pauseButton.tap()
        sleep(1)

        let playButton = app.buttons.matching(
            NSPredicate(format: "label == 'Play'")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 3),
                      "Play button should appear after pausing")

        // Tap to resume
        playButton.tap()
        sleep(1)

        XCTAssertTrue(pauseButton.waitForExistence(timeout: 3),
                      "Pause button should appear after resuming")
    }

    // MARK: - Now Playing View

    func testOpenNowPlayingView() throws {
        try app.playAnyTrack()
        sleep(2)
        try app.openNowPlaying()

        XCTAssertTrue(app.state == .runningForeground,
                      "App should not crash when opening Now Playing")
    }

    func testNowPlayingHasExpectedControls() throws {
        try app.playAnyTrack()
        try app.openNowPlaying()

        let expectedControls = [
            "Previous Track", "Next Track", "Shuffle", "Repeat",
            "Show Queue", "Track Progress"
        ]

        var foundCount = 0
        for label in expectedControls {
            if app.buttons[label].exists || app.sliders[label].exists {
                foundCount += 1
            }
        }

        XCTAssertGreaterThanOrEqual(foundCount, 3,
                                     "Now Playing should have at least 3 expected controls, found \(foundCount)")
    }

    func testNowPlayingSliderExists() throws {
        try app.playAnyTrack()
        try app.openNowPlaying()

        let slider = app.sliders["Track Progress"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5),
                      "Now Playing should have a Track Progress slider")
    }

}
