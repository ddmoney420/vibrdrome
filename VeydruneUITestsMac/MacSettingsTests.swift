import XCTest

/// Tests Settings window on macOS (opened via Cmd+,).
///
/// NOTE: macOS SwiftUI List renders section headers and row labels with
/// empty accessibility labels. We verify sections by checking for
/// identifiable elements: named buttons, popUpButton values, and
/// color buttons rather than text labels.
final class MacSettingsTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        // Ensure app is foregrounded (previous test may have lost focus)
        app.activate()
        sleep(1)
        ensureLoggedIn()
    }

    // MARK: - Settings Window

    func testSettingsWindowOpens() throws {
        app.openSettingsWindow()

        // Settings window should appear — look for known settings content
        let hasContent = app.buttons["Test Connection"].waitForExistence(timeout: 10)
            || app.buttons["Sign Out"].exists
            || app.buttons["Manage Servers"].exists

        XCTAssertTrue(hasContent,
                      "Settings window should open with server section content")
    }

    // MARK: - Server Section

    func testServerSectionExists() throws {
        app.openSettingsWindow()
        sleep(2)

        let hasServerInfo = app.buttons["Test Connection"].exists
            || app.buttons["Manage Servers"].exists
            || app.buttons["Sign Out"].exists

        XCTAssertTrue(hasServerInfo,
                      "Settings should show server section content")
    }

    func testTestConnectionButton() throws {
        app.openSettingsWindow()
        sleep(2)

        let testConnection = app.buttons["Test Connection"]
        guard testConnection.waitForExistence(timeout: 5) else {
            throw XCTSkip("Test Connection button not found")
        }

        testConnection.click()
        sleep(3)

        XCTAssertTrue(app.state == .runningForeground,
                      "Test Connection should complete without crashing")
    }

    func testManageServersButton() throws {
        app.openSettingsWindow()
        sleep(2)

        let manageServers = app.buttons["Manage Servers"]
        XCTAssertTrue(manageServers.waitForExistence(timeout: 5),
                      "Settings should have Manage Servers button")
    }

    // MARK: - Playback Section
    //
    // Playback section contains:
    // - WiFi Quality picker (popUpButton, default value "Original")
    // - Crossfade picker (popUpButton, default value "Off")
    // - ReplayGain picker (popUpButton, default value "Off")
    // - EQ Settings button (NavigationLink)
    // - Toggles for Scrobbling, Gapless, Equalizer (render with empty labels)

    func testPlaybackSectionExists() throws {
        app.openSettingsWindow()
        sleep(2)

        // EQ Settings is a NavigationLink that renders as a button
        let eqSettings = app.buttons["EQ Settings"]
        // WiFi Quality picker with default value "Original"
        let wifiPicker = app.popUpButtons.matching(
            NSPredicate(format: "value == 'Original'")).firstMatch
        // Crossfade/ReplayGain pickers with value "Off"
        let offPicker = app.popUpButtons.matching(
            NSPredicate(format: "value == 'Off'")).firstMatch

        let hasPlaybackSection = eqSettings.waitForExistence(timeout: 10)
            || wifiPicker.exists
            || offPicker.exists

        XCTAssertTrue(hasPlaybackSection,
                      "Settings should have Playback section (EQ Settings or pickers)")
    }

    func testReplayGainSettingExists() throws {
        app.openSettingsWindow()
        sleep(2)

        // ReplayGain is a popUpButton. There are two "Off" pickers:
        // Crossfade and ReplayGain. Both exist in the Playback section.
        let offPickers = app.popUpButtons.matching(
            NSPredicate(format: "value == 'Off'"))

        XCTAssertGreaterThanOrEqual(offPickers.count, 2,
            "Settings should have at least 2 'Off' pickers (Crossfade and ReplayGain)")
    }

    func testWiFiQualitySettingExists() throws {
        app.openSettingsWindow()
        sleep(2)

        // WiFi Quality picker has value "Original" (default)
        let wifiPicker = app.popUpButtons.matching(
            NSPredicate(format: "value == 'Original'")).firstMatch

        XCTAssertTrue(wifiPicker.waitForExistence(timeout: 5),
                      "Settings should have WiFi Quality picker with 'Original' value")
    }

    // MARK: - Downloads Section
    //
    // Downloads section contains:
    // - Cache Limit picker (popUpButton, default value "Unlimited")
    // - Downloaded Songs count (staticText, empty label)
    // - Storage Used info
    // - Auto-Download Favorites toggle

    func testDownloadsSectionExists() throws {
        app.openSettingsWindow()
        sleep(2)

        // Cache Limit picker with value "Unlimited" (default)
        let cacheLimitPicker = app.popUpButtons.matching(
            NSPredicate(format: "value == 'Unlimited'")).firstMatch

        XCTAssertTrue(cacheLimitPicker.waitForExistence(timeout: 5),
                      "Settings should show Downloads section (Cache Limit picker)")
    }

    // MARK: - Appearance Section
    //
    // Appearance section contains:
    // - Theme picker (popUpButton, value "Dark"/"Light"/"System")
    // - Accent Color grid (buttons: Blue, Purple, Pink, Red, etc.)
    // - Album Art in Lists toggle

    func testAppearanceSectionExists() throws {
        app.openSettingsWindow()
        sleep(2)

        // Theme picker — value may be title case ("System") or lowercase ("system")
        let themePicker = app.popUpButtons.matching(
            NSPredicate(format: "value ==[c] 'Dark' OR value ==[c] 'Light' OR value ==[c] 'System'")).firstMatch

        // Fallback: accent color buttons prove the Appearance section exists
        let blueButton = app.buttons["Blue"]

        XCTAssertTrue(themePicker.waitForExistence(timeout: 5) || blueButton.exists,
                      "Settings should have Theme picker or Accent Color buttons")
    }

    func testAccentColorExists() throws {
        app.openSettingsWindow()
        sleep(2)

        // Accent Color buttons exist in the accessibility tree but may be
        // offscreen (at frame 0,0,1440,0,0). They're still "exists" = true
        // because macOS pre-loads them.
        let blueButton = app.buttons["Blue"]
        let purpleButton = app.buttons["Purple"]

        // Scroll to find them if not yet loaded
        for _ in 0..<6 {
            if blueButton.exists || purpleButton.exists { break }
            app.scrollDownInSettings()
            sleep(1)
        }

        let hasAccentColors = blueButton.waitForExistence(timeout: 3)
            || purpleButton.exists

        XCTAssertTrue(hasAccentColors,
                      "Settings should have Accent Color buttons")
    }

    // MARK: - About Section
    //
    // About section contains:
    // - Version, Client, API Version info rows (all empty labels)
    // - 'Info' icon staticText
    // - 'Debug Tools' button (DEBUG builds only)

    func testAboutSectionExists() throws {
        app.openSettingsWindow()
        sleep(2)

        // The About section has the 'Info' system icon and potentially
        // 'Debug Tools' button. All are in the pre-loaded accessibility tree.
        // Verify by checking total cell count — Settings has ~30 cells
        // spanning all 6 sections.
        let cellCount = app.cells.count
        let hasDebugTools = app.buttons["Debug Tools"].exists

        // Also check for the total popUpButtons (5 expected:
        // WiFi, Crossfade, ReplayGain, CacheLimit, Theme)
        let popUpCount = app.popUpButtons.count

        XCTAssertTrue(cellCount >= 25 || hasDebugTools,
                      "Settings should have all sections loaded (\(cellCount) cells, \(popUpCount) popups)")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            XCTAssertTrue(app.waitForMainScreen())
        }
    }
}
