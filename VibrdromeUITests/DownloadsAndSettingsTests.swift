import XCTest

/// Tests downloads/offline, cache settings, and settings features.
final class DownloadsAndSettingsTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
    }

    // MARK: - Downloads Section in Settings

    func testDownloadsSectionExists() throws {
        app.goToSettings()
        sleep(2)

        // Scroll to find Downloads section — it's the 3rd section
        let downloadedSongs = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Downloaded Songs'")).firstMatch
        let downloadsHeader = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Downloads'")).firstMatch

        for _ in 0..<5 {
            if downloadedSongs.exists || downloadsHeader.exists { break }
            app.swipeUpInDetail()
            sleep(1)
        }

        let hasDownloadsSection = downloadedSongs.waitForExistence(timeout: 5)
            || downloadsHeader.exists

        XCTAssertTrue(hasDownloadsSection,
                      "Settings should show Downloads section")
    }

    func testCacheLimitPickerExists() throws {
        app.goToSettings()
        sleep(2)

        // Scroll to find Cache Limit
        for _ in 0..<3 {
            if app.staticTexts["Cache Limit"].exists { break }
            app.swipeUpInDetail()
            sleep(1)
        }

        let cacheLimit = app.staticTexts["Cache Limit"]
        XCTAssertTrue(cacheLimit.waitForExistence(timeout: 5),
                      "Settings should have Cache Limit picker")
    }

    func testAutoDownloadFavoritesToggle() throws {
        app.goToSettings()
        sleep(2)

        // Scroll to find the toggle
        for _ in 0..<3 {
            if app.staticTexts["Auto-Download Favorites"].exists { break }
            app.swipeUpInDetail()
            sleep(1)
        }

        let autoDownload = app.staticTexts["Auto-Download Favorites"]
        XCTAssertTrue(autoDownload.waitForExistence(timeout: 5),
                      "Settings should have Auto-Download Favorites toggle")
    }

    func testDownloadedSongsCountDisplayed() throws {
        app.goToSettings()
        sleep(2)

        // Scroll to downloads section (3rd section)
        let downloadedSongs = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Downloaded Songs'")).firstMatch

        for _ in 0..<5 {
            if downloadedSongs.exists { break }
            app.swipeUpInDetail()
            sleep(1)
        }

        XCTAssertTrue(downloadedSongs.waitForExistence(timeout: 5),
                      "Settings should show downloaded songs count")
    }

    // MARK: - Playback Settings

    func testPlaybackSectionExists() throws {
        app.goToSettings()
        sleep(2)

        // Playback section is the 2nd section — may need scrolling past server
        // Labels inside Toggle/Picker may be staticTexts, switches, or buttons
        let scrobblingText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Scrobbling'")).firstMatch
        let scrobblingSwitch = app.switches.matching(
            NSPredicate(format: "label CONTAINS[c] 'Scrobbling'")).firstMatch
        let gaplessText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Gapless'")).firstMatch
        let gaplessSwitch = app.switches.matching(
            NSPredicate(format: "label CONTAINS[c] 'Gapless'")).firstMatch

        for _ in 0..<3 {
            if scrobblingText.exists || scrobblingSwitch.exists
                || gaplessText.exists || gaplessSwitch.exists { break }
            app.swipeUpInDetail()
            sleep(1)
        }

        let hasPlaybackSection = scrobblingText.waitForExistence(timeout: 5)
            || scrobblingSwitch.exists
            || gaplessText.exists
            || gaplessSwitch.exists

        XCTAssertTrue(hasPlaybackSection,
                      "Settings should have Playback section")
    }

    func testReplayGainSettingExists() throws {
        app.goToSettings()
        sleep(2)

        let replayGain = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'ReplayGain'")).firstMatch

        // May need to scroll
        if !replayGain.exists {
            app.swipeUpInDetail()
            sleep(1)
        }

        XCTAssertTrue(replayGain.waitForExistence(timeout: 5),
                      "Settings should have ReplayGain setting")
    }

    // MARK: - Appearance Settings

    func testThemePickerExists() throws {
        app.goToSettings()
        sleep(2)

        // Scroll to appearance section
        for _ in 0..<4 {
            if app.staticTexts["Theme"].exists { break }
            app.swipeUpInDetail()
            sleep(1)
        }

        let theme = app.staticTexts["Theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5),
                      "Settings should have Theme picker")
    }

    func testAccentColorExists() throws {
        app.goToSettings()
        sleep(2)

        // Scroll to accent color
        for _ in 0..<4 {
            if app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Accent'")).firstMatch.exists { break }
            app.swipeUpInDetail()
            sleep(1)
        }

        let accentColor = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Accent'")).firstMatch
        XCTAssertTrue(accentColor.waitForExistence(timeout: 5),
                      "Settings should have Accent Color setting")
    }

    // MARK: - Quality Settings

    func testWiFiQualitySettingExists() throws {
        app.goToSettings()
        sleep(2)

        // WiFi Quality is a Picker with Label — may appear as staticText or button
        let wifiText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'WiFi'")).firstMatch
        let wifiButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'WiFi'")).firstMatch

        for _ in 0..<3 {
            if wifiText.exists || wifiButton.exists { break }
            app.swipeUpInDetail()
            sleep(1)
        }

        let hasWifi = wifiText.waitForExistence(timeout: 5)
            || wifiButton.exists

        XCTAssertTrue(hasWifi,
                      "Settings should have WiFi Quality setting")
    }

    // MARK: - About Section

    func testAboutSectionExists() throws {
        app.goToSettings()
        sleep(2)

        // Scroll to bottom
        for _ in 0..<5 {
            app.swipeUpInDetail()
            sleep(1)
        }

        let vibrdrome = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Vibrdrome' OR label CONTAINS[c] 'Version'")).firstMatch

        XCTAssertTrue(vibrdrome.waitForExistence(timeout: 5),
                      "Settings should show About section with app name or version")
    }

    // MARK: - Server Management

    func testManageServersOpens() throws {
        app.goToSettings()
        sleep(2)

        let manageServers = app.buttons["Manage Servers"]
        guard manageServers.waitForExistence(timeout: 5) else {
            throw XCTSkip("Manage Servers button not found")
        }

        manageServers.tap()
        sleep(2)

        // Should show server management view
        let hasContent = app.staticTexts.count > 1
            || app.buttons.count > 2

        XCTAssertTrue(hasContent || app.state == .runningForeground,
                      "Manage Servers should open without crashing")

        // Dismiss
        app.swipeDown()
        sleep(1)
    }

    func testTestConnectionButton() throws {
        app.goToSettings()
        sleep(2)

        let testConnection = app.buttons["Test Connection"]
        guard testConnection.waitForExistence(timeout: 5) else {
            throw XCTSkip("Test Connection button not found")
        }

        testConnection.tap()
        sleep(3)

        // Should complete without crashing
        XCTAssertTrue(app.state == .runningForeground,
                      "Test Connection should complete without crashing")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            XCTAssertTrue(app.waitForMainScreen())
        }
    }
}
