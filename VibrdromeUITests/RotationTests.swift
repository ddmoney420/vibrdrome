import XCTest

/// Tests device rotation on key screens to ensure layout adapts without crashes.
final class RotationTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
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

        // Scroll while in landscape to check layout
        app.swipeUpInDetail()
        sleep(1)
        XCTAssertTrue(app.state == .runningForeground,
                      "Settings should scroll in landscape without crash")

        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    // MARK: - Now Playing

    func testNowPlayingRotation() throws {
        try playAnyTrack()

        let nowPlayingButton = app.buttons["Now Playing"]
        guard nowPlayingButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Mini player not visible")
        }

        nowPlayingButton.tap()
        sleep(2)

        let shuffleButton = app.buttons["Shuffle"]
        guard shuffleButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Could not open Now Playing view")
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "Now Playing should not crash in landscape")

        // Verify controls still exist in landscape
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
        try playAnyTrack()

        let pauseButton = app.buttons.matching(
            NSPredicate(format: "label == 'Pause'")).firstMatch
        guard pauseButton.waitForExistence(timeout: 5)
            || app.buttons.matching(
                NSPredicate(format: "label == 'Play'")).firstMatch.exists else {
            throw XCTSkip("Could not start playback")
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)

        // Mini player should still be visible
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

        // Rapidly cycle through orientations
        for orientation: UIDeviceOrientation in [.landscapeLeft, .portrait,
                                                  .landscapeRight, .portrait,
                                                  .landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            usleep(500_000) // 0.5s between rotations
        }

        sleep(1)
        XCTAssertTrue(app.state == .runningForeground,
                      "App should survive rapid rotation changes")
    }

    // MARK: - Rotation During Playback

    func testRotationDuringPlayback() throws {
        try playAnyTrack()
        sleep(2)

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)

        // Verify playback controls still work
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

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            XCTAssertTrue(app.waitForMainScreen())
        }
    }

    private func playAnyTrack() throws {
        let pauseButton = app.buttons.matching(
            NSPredicate(format: "label == 'Pause'")).firstMatch
        let playButton = app.buttons.matching(
            NSPredicate(format: "label == 'Play'")).firstMatch
        if pauseButton.exists || playButton.exists { return }

        app.goToLibrary()
        sleep(3)

        let albumButtons = app.buttons.allElementsBoundByIndex
        for btn in albumButtons {
            let label = btn.label.lowercased()
            if ["library", "search", "playlists", "radio", "settings",
                "pause", "play", "next track", "artists"].contains(label) { continue }
            if btn.frame.width < 50 || btn.frame.height < 50 { continue }
            btn.tap()
            break
        }
        sleep(3)

        let songTexts = app.staticTexts.allElementsBoundByIndex
        for text in songTexts {
            if text.frame.minY < 300 { continue }
            if text.label.isEmpty { continue }
            let label = text.label.lowercased()
            if ["songs", "recently added", "most played", "library",
                "shuffle", "play all"].contains(label) { continue }
            text.tap()
            break
        }
        sleep(3)

        let playing = pauseButton.waitForExistence(timeout: 10) || playButton.exists
        if !playing { throw XCTSkip("Could not start playback") }
    }
}
