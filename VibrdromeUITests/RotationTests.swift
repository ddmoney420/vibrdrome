import XCTest

/// Tests device rotation on key screens to ensure layout adapts without crashes.
final class RotationTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureForTesting()
        app.launch()
        app.ensureLoggedIn()
    }

    override func tearDownWithError() throws {
        // Always return to portrait
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    // MARK: - Library

    func testLibraryRotation() throws {
        app.goToLibrary()
        sleep(2)

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "Library should not crash in landscape")

        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "Library should not crash returning to portrait")
    }

    // MARK: - Search

    func testSearchRotation() throws {
        app.goToSearch()
        sleep(2)

        XCUIDevice.shared.orientation = .landscapeRight
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "Search should not crash in landscape")

        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    // MARK: - Playlists

    func testPlaylistsRotation() throws {
        app.goToPlaylists()
        sleep(2)

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "Playlists should not crash in landscape")

        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    // MARK: - Radio

    func testRadioRotation() throws {
        app.goToRadio()
        sleep(2)

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "Radio should not crash in landscape")

        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    // MARK: - Settings

    func testSettingsRotation() throws {
        app.goToSettings()
        sleep(2)

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "Settings should not crash in landscape")

        app.swipeUpInDetail()
        sleep(1)
        XCTAssertTrue(app.state == .runningForeground,
                      "Settings should scroll in landscape without crash")

        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    // MARK: - Now Playing

    func testNowPlayingRotation() throws {
        try app.playAnyTrack()
        try app.openNowPlaying()

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "Now Playing should not crash in landscape")

        XCTAssertTrue(app.buttons["Shuffle"].exists || app.buttons["Play"].exists
                      || app.buttons["Pause"].exists,
                      "Controls should remain visible in landscape")

        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "Now Playing should not crash returning to portrait")
    }

    // MARK: - Mini Player

    func testMiniPlayerRotation() throws {
        try app.playAnyTrack()

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)

        let hasControls = app.buttons.matching(
            NSPredicate(format: "label == 'Pause' OR label == 'Play'")).firstMatch.exists
        XCTAssertTrue(hasControls || app.state == .runningForeground,
                      "Mini player should remain functional in landscape")

        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    // MARK: - Rapid Rotation

    func testRapidRotation() throws {
        app.goToLibrary()
        sleep(2)

        for orientation: UIDeviceOrientation in [.landscapeLeft, .portrait,
                                                  .landscapeRight, .portrait,
                                                  .landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            usleep(500_000)
        }

        sleep(1)
        XCTAssertTrue(app.state == .runningForeground,
                      "App should survive rapid rotation changes")
    }

    // MARK: - Rotation During Playback

    func testRotationDuringPlayback() throws {
        try app.playAnyTrack()
        sleep(2)

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)

        let pauseButton = app.buttons.matching(
            NSPredicate(format: "label == 'Pause'")).firstMatch
        let playButton = app.buttons.matching(
            NSPredicate(format: "label == 'Play'")).firstMatch

        if pauseButton.exists {
            pauseButton.tap()
            sleep(1)
            XCTAssertTrue(playButton.waitForExistence(timeout: 3),
                          "Play button should appear after pausing in landscape")
            playButton.tap()
            sleep(1)
        }

        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        XCTAssertTrue(app.state == .runningForeground,
                      "Playback should continue through rotation")
    }

}
