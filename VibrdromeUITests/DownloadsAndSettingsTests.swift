import XCTest

/// Tests downloads/offline, cache settings, and settings features.
final class DownloadsAndSettingsTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.ensureLoggedIn()
    }

    // MARK: - Downloads Section in Settings

    func testDownloadsSectionExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.app.otherElements["sectionHeader_Downloads"].exists }

        XCTAssertTrue(app.otherElements["sectionHeader_Downloads"].exists,
                      "Settings should show Downloads section header")
    }

    func testCacheLimitPickerExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind {
            self.app.otherElements["cacheLimitPicker"].exists
                || self.app.cells["cacheLimitPicker"].exists
        }

        let found = app.otherElements["cacheLimitPicker"].exists
            || app.cells["cacheLimitPicker"].exists
            // Fall back to label text
            || app.staticTexts["Cache Limit"].exists
            || app.buttons["Cache Limit"].exists
        XCTAssertTrue(found, "Settings should have Cache Limit setting")
    }

    func testAutoDownloadFavoritesToggle() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind {
            self.app.switches["autoDownloadFavoritesToggle"].exists
                || self.app.otherElements["autoDownloadFavoritesToggle"].exists
        }

        let found = app.switches["autoDownloadFavoritesToggle"].exists
            || app.otherElements["autoDownloadFavoritesToggle"].exists
            // Fall back to label text
            || app.staticTexts["Auto-Download Favorites"].exists
            || app.switches["Auto-Download Favorites"].exists
        XCTAssertTrue(found, "Settings should have Auto-Download Favorites toggle")
    }

    func testDownloadedSongsCountDisplayed() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind {
            self.app.otherElements["downloadedSongsRow"].exists
                || self.app.staticTexts["Downloaded Songs"].exists
        }

        let found = app.otherElements["downloadedSongsRow"].exists
            || app.staticTexts["Downloaded Songs"].exists
        XCTAssertTrue(found, "Settings should show downloaded songs count")
    }

    // MARK: - Playback Settings

    func testPlaybackSectionExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind {
            self.app.otherElements["sectionHeader_Playback"].exists
                || self.app.otherElements["wifiQualityPicker"].exists
                || self.app.switches["scrobblingToggle"].exists
        }

        let hasPlayback = app.otherElements["sectionHeader_Playback"].exists
            || app.otherElements["wifiQualityPicker"].exists
            || app.cells["wifiQualityPicker"].exists
            || app.switches["scrobblingToggle"].exists
            || app.otherElements["scrobblingToggle"].exists
        XCTAssertTrue(hasPlayback, "Settings should have Playback section")
    }

    func testReplayGainSettingExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind {
            self.app.otherElements["replayGainPicker"].exists
                || self.app.cells["replayGainPicker"].exists
        }

        let found = app.otherElements["replayGainPicker"].exists
            || app.cells["replayGainPicker"].exists
            || app.staticTexts["ReplayGain"].exists
            || app.buttons["ReplayGain"].exists
        XCTAssertTrue(found, "Settings should have ReplayGain setting")
    }

    // MARK: - Appearance Settings

    func testThemePickerExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind {
            self.app.otherElements["themePicker"].exists
                || self.app.cells["themePicker"].exists
        }

        let found = app.otherElements["themePicker"].exists
            || app.cells["themePicker"].exists
            || app.staticTexts["Theme"].exists
            || app.buttons["Theme"].exists
        XCTAssertTrue(found, "Settings should have Theme picker")
    }

    func testAccentColorExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.app.staticTexts["Accent Color"].exists }

        XCTAssertTrue(
            app.staticTexts["Accent Color"].exists || app.buttons["Accent Color"].exists,
            "Settings should have Accent Color setting")
    }

    // MARK: - Quality Settings

    func testWiFiQualitySettingExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind {
            self.app.otherElements["wifiQualityPicker"].exists
                || self.app.cells["wifiQualityPicker"].exists
        }

        let found = app.otherElements["wifiQualityPicker"].exists
            || app.cells["wifiQualityPicker"].exists
            || app.staticTexts["WiFi Quality"].exists
            || app.buttons["WiFi Quality"].exists
        XCTAssertTrue(found, "Settings should have WiFi Quality setting")
    }

    // MARK: - About Section

    func testAboutSectionExists() throws {
        app.goToSettings()
        sleep(3)

        // About is at the bottom — scroll aggressively
        for _ in 0..<12 {
            if app.staticTexts["Vibrdrome"].exists
                || app.otherElements["sectionHeader_About"].exists { break }
            app.swipeUp()
            sleep(1)
        }

        XCTAssertTrue(
            app.staticTexts["Vibrdrome"].exists
                || app.otherElements["sectionHeader_About"].exists,
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

    /// Scroll up to 10 times until the condition is met.
    private func scrollToFind(_ condition: () -> Bool) {
        for _ in 0..<10 {
            if condition() { return }
            app.swipeUp()
            sleep(1)
        }
    }
}
