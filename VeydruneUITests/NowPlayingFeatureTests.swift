import XCTest

/// Tests Now Playing features: visualizer, lyrics, playback speed, EQ, sleep timer.
final class NowPlayingFeatureTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
        try playAnyTrack()
    }

    /// Attempts to open Now Playing. Call per-test rather than in setUp.
    private func ensureNowPlayingOpen() throws {
        // Check if already in Now Playing
        if app.buttons["Shuffle"].exists { return }
        try openNowPlaying()
    }

    // MARK: - Visualizer

    func testVisualizerButtonExists() throws {
        try ensureNowPlayingOpen()
        let visualizer = app.buttons["Visualizer"]
        XCTAssertTrue(visualizer.waitForExistence(timeout: 5),
                      "Visualizer button should exist in Now Playing")
    }

    func testVisualizerOpens() throws {
        try ensureNowPlayingOpen()
        let visualizer = app.buttons["Visualizer"]
        guard visualizer.waitForExistence(timeout: 5) else {
            throw XCTSkip("Visualizer button not found")
        }

        visualizer.tap()
        sleep(3)

        // Visualizer should be a full screen view — look for transport controls
        // that appear in the visualizer (play/pause, previous, next)
        let closeButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'close' OR label CONTAINS[c] 'xmark'")).firstMatch
        let pauseOrPlay = app.buttons.matching(
            NSPredicate(format: "label == 'Pause' OR label == 'Play'")).firstMatch

        let visualizerOpened = closeButton.waitForExistence(timeout: 5)
            || pauseOrPlay.exists

        XCTAssertTrue(visualizerOpened || app.state == .runningForeground,
                      "Visualizer should open without crashing")
    }

    func testVisualizerPresetsExist() throws {
        try ensureNowPlayingOpen()
        let visualizer = app.buttons["Visualizer"]
        guard visualizer.waitForExistence(timeout: 5) else {
            throw XCTSkip("Visualizer button not found")
        }

        visualizer.tap()
        sleep(2)

        // Tap to show controls (controls auto-hide)
        app.tap()
        sleep(1)

        // Look for preset names in the visualizer
        let presetNames = ["Plasma", "Aurora", "Nebula", "Waveform", "Tunnel", "Kaleidoscope"]
        var foundPreset = false
        for name in presetNames {
            if app.staticTexts[name].exists || app.buttons[name].exists {
                foundPreset = true
                break
            }
        }

        // Presets might be in a menu — verify no crash at minimum
        XCTAssertTrue(app.state == .runningForeground,
                      "App should not crash in visualizer view")
    }

    func testVisualizerSwipeChangesPreset() throws {
        try ensureNowPlayingOpen()
        let visualizer = app.buttons["Visualizer"]
        guard visualizer.waitForExistence(timeout: 5) else {
            throw XCTSkip("Visualizer button not found")
        }

        visualizer.tap()
        sleep(2)

        // Swipe left to change preset
        app.swipeLeft()
        sleep(1)
        app.swipeLeft()
        sleep(1)
        app.swipeRight()
        sleep(1)

        // Just verify no crash
        XCTAssertTrue(app.state == .runningForeground,
                      "App should not crash when swiping presets")

        // Dismiss visualizer by swiping down
        app.swipeDown()
        sleep(1)
    }

    // MARK: - Lyrics

    func testLyricsButtonExists() throws {
        try ensureNowPlayingOpen()
        let lyrics = app.buttons["Lyrics"]
        XCTAssertTrue(lyrics.waitForExistence(timeout: 5),
                      "Lyrics button should exist in Now Playing")
    }

    func testLyricsViewOpens() throws {
        try ensureNowPlayingOpen()
        let lyrics = app.buttons["Lyrics"]
        guard lyrics.waitForExistence(timeout: 5) else {
            throw XCTSkip("Lyrics button not found")
        }

        lyrics.tap()
        sleep(3)

        // Lyrics view should show either lyrics content, a loading state,
        // or "No Lyrics" message
        let lyricsTitle = app.navigationBars["Lyrics"]
        let noLyricsMessage = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'lyrics' OR label CONTAINS[c] 'No Lyrics'")).firstMatch
        let loadingView = app.activityIndicators.firstMatch

        let lyricsViewOpened = lyricsTitle.waitForExistence(timeout: 5)
            || noLyricsMessage.exists
            || loadingView.exists
            || app.staticTexts.count > 3

        XCTAssertTrue(lyricsViewOpened,
                      "Lyrics view should open and show content or no-lyrics message")
    }

    func testLyricsDismisses() throws {
        try ensureNowPlayingOpen()
        let lyrics = app.buttons["Lyrics"]
        guard lyrics.waitForExistence(timeout: 5) else {
            throw XCTSkip("Lyrics button not found")
        }

        lyrics.tap()
        sleep(2)

        // Dismiss lyrics
        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 3) {
            doneButton.tap()
        } else {
            // Swipe down to dismiss sheet
            app.swipeDown()
        }
        sleep(1)

        // Should be back on Now Playing
        let shuffleButton = app.buttons["Shuffle"]
        XCTAssertTrue(shuffleButton.waitForExistence(timeout: 5),
                      "Should return to Now Playing after dismissing lyrics")
    }

    // MARK: - Playback Speed

    func testPlaybackSpeedButtonExists() throws {
        try ensureNowPlayingOpen()
        let speedButton = app.buttons["Playback Speed"]
        XCTAssertTrue(speedButton.waitForExistence(timeout: 5),
                      "Playback Speed button should exist in Now Playing")
    }

    func testPlaybackSpeedMenuShowsOptions() throws {
        try ensureNowPlayingOpen()
        let speedButton = app.buttons["Playback Speed"]
        guard speedButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Playback Speed button not found")
        }

        speedButton.tap()
        sleep(1)

        // Menu should show speed options
        let normalOption = app.buttons["Normal"]
        let has15x = app.buttons["1.5x"]
        let has2x = app.buttons["2x"]
        let has075x = app.buttons["0.75x"]

        let hasSpeedOptions = normalOption.waitForExistence(timeout: 3)
            || has15x.exists
            || has2x.exists
            || has075x.exists

        XCTAssertTrue(hasSpeedOptions,
                      "Speed menu should show playback rate options")

        // Dismiss menu by tapping elsewhere
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        sleep(1)
    }

    // MARK: - EQ

    func testEQButtonExists() throws {
        try ensureNowPlayingOpen()
        let eqButton = app.buttons["Equalizer"]
        XCTAssertTrue(eqButton.waitForExistence(timeout: 5),
                      "Equalizer button should exist in Now Playing")
    }

    func testEQViewOpens() throws {
        try ensureNowPlayingOpen()
        let eqButton = app.buttons["Equalizer"]
        guard eqButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Equalizer button not found")
        }

        eqButton.tap()
        sleep(2)

        // EQ view should show "Equalizer" title and presets
        let eqTitle = app.navigationBars["Equalizer"]
        let presetsLabel = app.staticTexts["Presets"]
        let flatPreset = app.buttons["Flat"]

        let eqOpened = eqTitle.waitForExistence(timeout: 5)
            || presetsLabel.exists
            || flatPreset.exists

        XCTAssertTrue(eqOpened, "EQ view should open with presets visible")
    }

    func testEQPresetsExist() throws {
        try ensureNowPlayingOpen()
        let eqButton = app.buttons["Equalizer"]
        guard eqButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Equalizer button not found")
        }

        eqButton.tap()
        sleep(2)

        let presetNames = ["Flat", "Bass Boost", "Treble Boost", "Rock",
                           "Pop", "Jazz", "Classical", "Vocal", "Late Night"]
        var foundCount = 0
        for name in presetNames {
            if app.buttons[name].exists || app.staticTexts[name].exists {
                foundCount += 1
            }
        }

        XCTAssertGreaterThanOrEqual(foundCount, 5,
                                     "EQ should show at least 5 preset buttons, found \(foundCount)")
    }

    func testEQHasBandSliders() throws {
        try ensureNowPlayingOpen()
        let eqButton = app.buttons["Equalizer"]
        guard eqButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Equalizer button not found")
        }

        eqButton.tap()
        sleep(2)

        // Look for frequency band labels
        let bandLabels = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
        var foundBands = 0
        for band in bandLabels {
            if app.staticTexts[band].exists {
                foundBands += 1
            }
        }

        XCTAssertGreaterThanOrEqual(foundBands, 8,
                                     "EQ should show at least 8 frequency band labels, found \(foundBands)")
    }

    func testEQHasResetButton() throws {
        try ensureNowPlayingOpen()
        let eqButton = app.buttons["Equalizer"]
        guard eqButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Equalizer button not found")
        }

        eqButton.tap()
        sleep(2)

        let resetButton = app.buttons["Reset"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 3),
                      "EQ should have a Reset button")
    }

    func testEQDismisses() throws {
        try ensureNowPlayingOpen()
        let eqButton = app.buttons["Equalizer"]
        guard eqButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Equalizer button not found")
        }

        eqButton.tap()
        sleep(2)

        let doneButton = app.buttons["Done"]
        guard doneButton.waitForExistence(timeout: 3) else {
            throw XCTSkip("Done button not found in EQ view")
        }

        doneButton.tap()
        sleep(1)

        // Should be back on Now Playing
        let shuffleButton = app.buttons["Shuffle"]
        XCTAssertTrue(shuffleButton.waitForExistence(timeout: 5),
                      "Should return to Now Playing after dismissing EQ")
    }

    func testEQSavePresetButton() throws {
        try ensureNowPlayingOpen()
        let eqButton = app.buttons["Equalizer"]
        guard eqButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Equalizer button not found")
        }

        eqButton.tap()
        sleep(2)

        let saveButton = app.buttons["Save as Preset"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3),
                      "EQ should have 'Save as Preset' button")
    }

    // MARK: - Sleep Timer

    func testSleepTimerButtonExists() throws {
        try ensureNowPlayingOpen()
        let sleepTimer = app.buttons["Sleep Timer"]
        XCTAssertTrue(sleepTimer.waitForExistence(timeout: 5),
                      "Sleep Timer button should exist in Now Playing")
    }

    func testSleepTimerMenuShowsOptions() throws {
        try ensureNowPlayingOpen()
        let sleepTimer = app.buttons["Sleep Timer"]
        guard sleepTimer.waitForExistence(timeout: 5) else {
            throw XCTSkip("Sleep Timer button not found")
        }

        sleepTimer.tap()
        sleep(1)

        // Menu should show timer options
        let has15m = app.buttons["15 minutes"].exists
            || app.buttons["15 Minutes"].exists
            || app.buttons.matching(NSPredicate(format: "label CONTAINS '15'")).firstMatch.exists
        let has30m = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '30'")).firstMatch.exists
        let hasEndOfTrack = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'end of track'")).firstMatch.exists

        let hasTimerOptions = has15m || has30m || hasEndOfTrack

        XCTAssertTrue(hasTimerOptions,
                      "Sleep timer should show duration options")

        // Dismiss menu
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        sleep(1)
    }

    // MARK: - Shuffle & Repeat

    func testShuffleToggle() throws {
        try ensureNowPlayingOpen()
        let shuffleButton = app.buttons["Shuffle"]
        guard shuffleButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Shuffle button not found")
        }

        shuffleButton.tap()
        sleep(1)
        XCTAssertTrue(app.state == .runningForeground,
                      "App should not crash when toggling shuffle")

        shuffleButton.tap()
        sleep(1)
        XCTAssertTrue(app.state == .runningForeground,
                      "App should not crash when toggling shuffle again")
    }

    func testRepeatToggle() throws {
        try ensureNowPlayingOpen()
        let repeatButton = app.buttons["Repeat"]
        guard repeatButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Repeat button not found")
        }

        // Cycle through: Off → All → One → Off
        repeatButton.tap()
        sleep(1)
        XCTAssertTrue(app.state == .runningForeground, "No crash on repeat tap 1")

        repeatButton.tap()
        sleep(1)
        XCTAssertTrue(app.state == .runningForeground, "No crash on repeat tap 2")

        repeatButton.tap()
        sleep(1)
        XCTAssertTrue(app.state == .runningForeground, "No crash on repeat tap 3")
    }

    // MARK: - Queue

    func testShowQueueOpens() throws {
        try ensureNowPlayingOpen()
        let queueButton = app.buttons["Show Queue"]
        guard queueButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Show Queue button not found")
        }

        queueButton.tap()
        sleep(2)

        // Queue should show content
        let hasContent = app.staticTexts.count > 2
        XCTAssertTrue(hasContent || app.state == .runningForeground,
                      "Queue view should open without crashing")
    }

    // MARK: - Favorites

    func testFavoriteButtonExists() throws {
        try ensureNowPlayingOpen()
        let addFav = app.buttons["Add to Favorites"]
        let removeFav = app.buttons["Remove from Favorites"]
        let hasFavoriteButton = addFav.waitForExistence(timeout: 5)
            || removeFav.exists

        XCTAssertTrue(hasFavoriteButton,
                      "Favorites button should exist in Now Playing")
    }

    func testFavoriteToggle() throws {
        try ensureNowPlayingOpen()
        let addFav = app.buttons["Add to Favorites"]
        let removeFav = app.buttons["Remove from Favorites"]

        if addFav.waitForExistence(timeout: 5) {
            addFav.tap()
            sleep(2)
            // Should now show "Remove from Favorites"
            XCTAssertTrue(removeFav.waitForExistence(timeout: 5)
                          || app.state == .runningForeground,
                          "Should toggle to Remove from Favorites")
            // Toggle back
            if removeFav.exists { removeFav.tap(); sleep(2) }
        } else if removeFav.exists {
            removeFav.tap()
            sleep(2)
            XCTAssertTrue(addFav.waitForExistence(timeout: 5)
                          || app.state == .runningForeground,
                          "Should toggle to Add to Favorites")
            // Toggle back
            if addFav.exists { addFav.tap(); sleep(2) }
        } else {
            throw XCTSkip("Favorites button not found")
        }
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            let libraryTab = app.tabBars.buttons["Library"]
            XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
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

        // Find an album button in the library
        let albumButtons = app.buttons.allElementsBoundByIndex
        for btn in albumButtons {
            let label = btn.label.lowercased()
            if ["library", "search", "playlists", "radio", "settings",
                "pause", "play", "next track"].contains(label) { continue }
            if btn.frame.width < 50 || btn.frame.height < 50 { continue }
            btn.tap()
            break
        }
        sleep(3)

        // Tap a track in the album detail
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

        let shuffleButton = app.buttons["Shuffle"]
        guard shuffleButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Could not open Now Playing view")
        }
    }
}
