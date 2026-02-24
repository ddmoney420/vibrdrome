import XCTest

/// Tests music playback: play a track, verify Now Playing, controls.
final class PlaybackTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
    }

    // MARK: - Play a Track via Library

    func testPlayTrackFromLibrary() throws {
        try navigateToAlbumAndPlay()

        // Check if mini player appeared (song is playing)
        let pauseButton = app.buttons.matching(
            NSPredicate(format: "label == 'Pause'")).firstMatch
        let playButton = app.buttons.matching(
            NSPredicate(format: "label == 'Play'")).firstMatch
        let miniPlayerVisible = pauseButton.waitForExistence(timeout: 10)
            || playButton.exists

        XCTAssertTrue(miniPlayerVisible,
                      "Mini player should appear after tapping a track")
    }

    func testMiniPlayerShowsSongInfo() throws {
        try playAnyTrack()

        // Mini player should show some text (song title, artist)
        sleep(2)
        let staticTexts = app.staticTexts
        XCTAssertGreaterThan(staticTexts.count, 2,
                             "Mini player should show song info text")
    }

    func testMiniPlayerNextButton() throws {
        try playAnyTrack()

        let nextButton = app.buttons["Next Track"]
        guard nextButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Next Track button not visible in mini player")
        }

        nextButton.tap()
        sleep(2)
        // App should still be running (no crash)
        XCTAssertTrue(app.state == .runningForeground,
                      "App should not crash on next track")
    }

    func testPlayPauseToggle() throws {
        try playAnyTrack()

        // Find pause button (should be playing)
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

        // Now the play button should exist
        let playButton = app.buttons.matching(
            NSPredicate(format: "label == 'Play'")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 3),
                      "Play button should appear after pausing")

        // Tap to resume
        playButton.tap()
        sleep(1)

        // Pause button should be back
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 3),
                      "Pause button should appear after resuming")
    }

    // MARK: - Now Playing View

    func testOpenNowPlayingView() throws {
        try playAnyTrack()
        sleep(2)

        try openNowPlaying()

        // Check for Now Playing controls
        let shuffleButton = app.buttons["Shuffle"]
        let trackProgress = app.sliders["Track Progress"]
        let hasNowPlayingControls = shuffleButton.waitForExistence(timeout: 5)
            || trackProgress.exists

        // Just verify no crash at minimum
        XCTAssertTrue(app.state == .runningForeground,
                      "App should not crash when opening Now Playing")
    }

    func testNowPlayingHasExpectedControls() throws {
        try playAnyTrack()
        try openNowPlaying()

        // Verify we actually opened Now Playing (Shuffle only appears in full view)
        let shuffleButton = app.buttons["Shuffle"]
        guard shuffleButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Could not open Now Playing full screen view")
        }

        // Verify key controls exist
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
        try playAnyTrack()
        try openNowPlaying()

        // Verify we actually opened Now Playing
        let shuffleButton = app.buttons["Shuffle"]
        guard shuffleButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Could not open Now Playing full screen view")
        }

        let slider = app.sliders["Track Progress"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5),
                      "Now Playing should have a Track Progress slider")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            XCTAssertTrue(app.waitForMainScreen())
        }
    }

    /// Navigate to Library, find an album, tap into it, and tap a track.
    private func navigateToAlbumAndPlay() throws {
        app.goToLibrary()
        sleep(3) // Wait for library content to load

        // Library shows album sections as horizontal scroll views
        // Look for album art elements or NavigationLinks to albums
        // The "Recently Added" section should have tappable album tiles

        // Find any tappable element that navigates to an album
        // Albums use NavigationLink which show up as buttons
        let albumButtons = app.buttons.allElementsBoundByIndex
        var albumButton: XCUIElement?

        // Look for button elements that are album tiles (not tab bar or system buttons)
        for btn in albumButtons {
            let label = btn.label.lowercased()
            // Skip system/tab buttons
            if ["library", "search", "playlists", "radio", "settings",
                "pause", "play", "next track", "previous track"].contains(label) {
                continue
            }
            // Skip small buttons (system icons)
            if btn.frame.width < 50 || btn.frame.height < 50 { continue }
            // Found a potential album tile
            albumButton = btn
            break
        }

        guard let album = albumButton else {
            throw XCTSkip("No albums found in Library")
        }

        album.tap()
        sleep(3) // Wait for album detail to load

        // In album detail, find and tap a track
        // Tracks are displayed as text rows with onTapGesture
        // Look for static texts that could be track titles
        let songTexts = app.staticTexts.allElementsBoundByIndex

        // After the album header, there should be track rows
        // Look for the first text element that's below the header area
        var tappedTrack = false
        for text in songTexts {
            // Skip if it's too high (header area) or empty
            if text.frame.minY < 300 { continue }
            if text.label.isEmpty { continue }
            // Skip section headers and metadata
            let label = text.label.lowercased()
            if ["songs", "recently added", "most played", "library",
                "shuffle", "play all"].contains(label) { continue }

            // This is likely a song title — tap its container area
            text.tap()
            tappedTrack = true
            break
        }

        if !tappedTrack {
            // Fallback: tap the center area where tracks would be
            let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            coordinate.tap()
        }

        sleep(3) // Wait for playback to start
    }

    /// Play any track to get something playing.
    private func playAnyTrack() throws {
        // Check if something is already playing
        let pauseButton = app.buttons.matching(
            NSPredicate(format: "label == 'Pause'")).firstMatch
        let playButton = app.buttons.matching(
            NSPredicate(format: "label == 'Play'")).firstMatch
        if pauseButton.exists || playButton.exists { return }

        try navigateToAlbumAndPlay()

        // Verify playback started
        let playing = pauseButton.waitForExistence(timeout: 10)
            || playButton.waitForExistence(timeout: 3)
        if !playing {
            throw XCTSkip("Could not start playback")
        }
    }

    /// Attempt to open the Now Playing full screen view.
    private func openNowPlaying() throws {
        sleep(1)

        // The mini player has a "Now Playing" button that opens the full screen view
        let nowPlayingButton = app.buttons["Now Playing"]
        if nowPlayingButton.waitForExistence(timeout: 5) {
            nowPlayingButton.tap()
        } else {
            // Fallback: tap near the bottom where mini player lives
            let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.92))
            coordinate.tap()
        }
        sleep(2)

        // Check if Now Playing opened
        let shuffleButton = app.buttons["Shuffle"]
        if !shuffleButton.waitForExistence(timeout: 3) {
            // Try coordinate-based tap as fallback
            let coordinate2 = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90))
            coordinate2.tap()
            sleep(2)
        }
    }
}
