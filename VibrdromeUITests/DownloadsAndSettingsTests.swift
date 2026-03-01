import XCTest

/// Tests downloads/offline, cache settings, and settings features.
final class DownloadsAndSettingsTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureForTesting()
        app.launch()
        app.ensureLoggedIn()
    }

    // MARK: - Downloads Section in Settings

    func testDownloadsSectionExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.findByIdentifier("sectionHeader_Downloads") }

        XCTAssertTrue(findByIdentifier("sectionHeader_Downloads"),
                      "Settings should show Downloads section header")
    }

    func testCacheLimitPickerExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.findByIdentifier("cacheLimitPicker") }

        XCTAssertTrue(findByIdentifier("cacheLimitPicker"),
                      "Settings should have Cache Limit setting")
    }

    func testAutoDownloadFavoritesToggle() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.findByIdentifier("autoDownloadFavoritesToggle") }

        XCTAssertTrue(findByIdentifier("autoDownloadFavoritesToggle"),
                      "Settings should have Auto-Download Favorites toggle")
    }

    func testDownloadedSongsCountDisplayed() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.findByIdentifier("downloadedSongsRow") }

        XCTAssertTrue(findByIdentifier("downloadedSongsRow"),
                      "Settings should show downloaded songs count")
    }

    // MARK: - Playback Settings

    func testPlaybackSectionExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind {
            self.findByIdentifier("sectionHeader_Playback")
                || self.findByIdentifier("wifiQualityPicker")
                || self.findByIdentifier("scrobblingToggle")
        }

        let hasPlayback = findByIdentifier("sectionHeader_Playback")
            || findByIdentifier("wifiQualityPicker")
            || findByIdentifier("scrobblingToggle")
        XCTAssertTrue(hasPlayback, "Settings should have Playback section")
    }

    func testReplayGainSettingExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.findByIdentifier("replayGainPicker") }

        XCTAssertTrue(findByIdentifier("replayGainPicker"),
                      "Settings should have ReplayGain setting")
    }

    // MARK: - Appearance Settings

    func testThemePickerExists() throws {
        app.goToSettings()
        sleep(3)

        scrollToFind { self.findByIdentifier("themePicker") }

        XCTAssertTrue(findByIdentifier("themePicker"),
                      "Settings should have Theme picker")
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

        scrollToFind { self.findByIdentifier("wifiQualityPicker") }

        XCTAssertTrue(findByIdentifier("wifiQualityPicker"),
                      "Settings should have WiFi Quality setting")
    }

    // MARK: - About Section

    func testAboutSectionExists() throws {
        app.goToSettings()
        sleep(3)

        // About is at the bottom — scroll aggressively
        for _ in 0..<12 {
            if app.staticTexts["Vibrdrome"].exists
                || findByIdentifier("sectionHeader_About") { break }
            app.swipeUp()
            sleep(1)
        }

        XCTAssertTrue(
            app.staticTexts["Vibrdrome"].exists
                || findByIdentifier("sectionHeader_About"),
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

    /// Search all element types for an accessibilityIdentifier. This is needed
    /// because iOS 26 SwiftUI renders Picker/Toggle/Section headers as varying
    /// element types that don't match `buttons`, `otherElements`, etc. reliably.
    private func findByIdentifier(_ identifier: String) -> Bool {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
    }

    /// Scroll up to 10 times until the condition is met.
    private func scrollToFind(_ condition: () -> Bool) {
        for _ in 0..<10 {
            if condition() { return }
            app.swipeUp()
            sleep(1)
        }
    }
}
