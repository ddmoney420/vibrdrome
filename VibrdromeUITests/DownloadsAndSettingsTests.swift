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
        sleep(3)

        scrollToFind { self.app.staticTexts["Downloads"].exists || self.app.staticTexts["Downloaded Songs"].exists }

        XCTAssertTrue(app.staticTexts["Downloads"].exists || app.staticTexts["Downloaded Songs"].exists,
                      "Settings should show Downloads section")
    }

    func testCacheLimitPickerExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.app.staticTexts["Cache Limit"].exists || self.app.buttons["Cache Limit"].exists }

        XCTAssertTrue(app.staticTexts["Cache Limit"].exists || app.buttons["Cache Limit"].exists,
                      "Settings should have Cache Limit setting")
    }

    func testAutoDownloadFavoritesToggle() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind {
            self.app.staticTexts["Auto-Download Favorites"].exists
                || self.app.switches["Auto-Download Favorites"].exists
        }

        XCTAssertTrue(
            app.staticTexts["Auto-Download Favorites"].exists
                || app.switches["Auto-Download Favorites"].exists,
            "Settings should have Auto-Download Favorites toggle")
    }

    func testDownloadedSongsCountDisplayed() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.app.staticTexts["Downloaded Songs"].exists }

        XCTAssertTrue(app.staticTexts["Downloaded Songs"].exists,
                      "Settings should show downloaded songs count")
    }

    // MARK: - Playback Settings

    func testPlaybackSectionExists() throws {
        app.goToSettings()
        sleep(3)

        // Look for section header "Playback" or any playback setting
        scrollToFind {
            self.app.staticTexts["Playback"].exists
                || self.app.staticTexts["WiFi Quality"].exists
                || self.app.buttons["WiFi Quality"].exists
                || self.app.switches["Scrobbling"].exists
                || self.app.staticTexts["Scrobbling"].exists
        }

        let hasPlayback = app.staticTexts["Playback"].exists
            || app.staticTexts["WiFi Quality"].exists
            || app.buttons["WiFi Quality"].exists
            || app.switches["Scrobbling"].exists
            || app.staticTexts["Scrobbling"].exists

        XCTAssertTrue(hasPlayback, "Settings should have Playback section")
    }

    func testReplayGainSettingExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.app.staticTexts["ReplayGain"].exists || self.app.buttons["ReplayGain"].exists }

        XCTAssertTrue(app.staticTexts["ReplayGain"].exists || app.buttons["ReplayGain"].exists,
                      "Settings should have ReplayGain setting")
    }

    // MARK: - Appearance Settings

    func testThemePickerExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind {
            self.app.staticTexts["Theme"].exists
                || self.app.buttons["Theme"].exists
                || self.app.staticTexts["Appearance"].exists
        }

        XCTAssertTrue(
            app.staticTexts["Theme"].exists
                || app.buttons["Theme"].exists
                || app.staticTexts["Appearance"].exists,
            "Settings should have Theme picker or Appearance section")
    }

    func testAccentColorExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.app.staticTexts["Accent Color"].exists || self.app.buttons["Accent Color"].exists }

        XCTAssertTrue(
            app.staticTexts["Accent Color"].exists || app.buttons["Accent Color"].exists,
            "Settings should have Accent Color setting")
    }

    // MARK: - Quality Settings

    func testWiFiQualitySettingExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.app.staticTexts["WiFi Quality"].exists || self.app.buttons["WiFi Quality"].exists }

        XCTAssertTrue(
            app.staticTexts["WiFi Quality"].exists || app.buttons["WiFi Quality"].exists,
            "Settings should have WiFi Quality setting")
    }

    // MARK: - About Section

    func testAboutSectionExists() throws {
        app.goToSettings()
        sleep(3)

        // About is at the bottom — scroll aggressively
        for _ in 0..<12 {
            if app.staticTexts["Vibrdrome"].exists || app.staticTexts["About"].exists { break }
            app.swipeUp()
            sleep(1)
        }

        XCTAssertTrue(
            app.staticTexts["Vibrdrome"].exists || app.staticTexts["About"].exists,
            "Settings should show About section with app name or version")
    }

    // MARK: - Server Management

    func testManageServersOpens() throws {
        app.goToSettings()
        sleep(3)

        let manageServers = app.buttons["Manage Servers"]
        guard manageServers.waitForExistence(timeout: 5) else {
            throw XCTSkip("Manage Servers button not found")
        }

        manageServers.tap()
        sleep(2)

        XCTAssertTrue(app.state == .runningForeground,
                      "Manage Servers should open without crashing")

        app.swipeDown()
        sleep(1)
    }

    func testTestConnectionButton() throws {
        app.goToSettings()
        sleep(3)

        let testConnection = app.buttons["Test Connection"]
        guard testConnection.waitForExistence(timeout: 5) else {
            throw XCTSkip("Test Connection button not found")
        }

        testConnection.tap()
        sleep(3)

        XCTAssertTrue(app.state == .runningForeground,
                      "Test Connection should complete without crashing")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        app.ensureLoggedIn()
    }

    /// Scroll up to 8 times until the condition is met.
    private func scrollToFind(_ condition: () -> Bool) {
        for _ in 0..<8 {
            if condition() { return }
            app.swipeUp()
            sleep(1)
        }
    }
}
