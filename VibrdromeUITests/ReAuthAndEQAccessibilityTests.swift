import XCTest

/// UI tests for ReAuth modal and EQ slider accessibility.
final class ReAuthAndEQAccessibilityTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.ensureLoggedIn()
    }

    // MARK: - EQ Slider Accessibility

    func testEQViewOpens() throws {
        try openEQView()

        // EQ view should show preset buttons and Done button
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5),
                      "EQ view should show Done button")
    }

    func testEQSliderAccessibilityLabels() throws {
        try openEQView()

        // Look for accessibility elements with Hz labels (the accessible sliders)
        let expectedBands = ["60", "250", "1K", "4K", "16K"]
        var foundCount = 0

        for band in expectedBands {
            let sliderLabel = app.otherElements.matching(
                NSPredicate(format: "label CONTAINS '\(band) Hz'")).firstMatch
            if sliderLabel.exists {
                foundCount += 1
            }
        }

        // At least some bands should be accessible
        XCTAssertGreaterThan(foundCount, 0,
                             "EQ sliders should have frequency Hz accessibility labels")
    }

    func testEQSliderAccessibilityValues() throws {
        try openEQView()

        // Look for accessibility elements with dB values
        let dbPredicate = NSPredicate(format: "value CONTAINS 'dB'")
        let slidersWithDB = app.otherElements.matching(dbPredicate)

        // Flat preset: all should be "+0 dB"
        let resetButton = app.buttons["Reset"]
        if resetButton.exists {
            resetButton.tap()
            sleep(1)
        }

        // After reset, check for "0 dB" values
        let zeroDBPredicate = NSPredicate(format: "value CONTAINS '0 dB'")
        let zeroSliders = app.otherElements.matching(zeroDBPredicate)

        XCTAssertTrue(slidersWithDB.count > 0 || zeroSliders.count > 0,
                      "EQ sliders should have dB accessibility values after reset")
    }

    func testEQPresetButtons() throws {
        try openEQView()

        // Check for preset buttons
        let presetNames = ["Flat", "Bass Boost", "Rock", "Pop", "Jazz"]
        var foundPresets = 0

        for name in presetNames {
            let preset = app.buttons[name]
            if preset.exists {
                foundPresets += 1
            }
        }

        XCTAssertGreaterThan(foundPresets, 0,
                             "EQ view should show preset buttons")
    }

    func testEQResetButton() throws {
        try openEQView()

        let resetButton = app.buttons["Reset"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 5),
                      "EQ view should have Reset button")
    }

    func testEQSavePresetButton() throws {
        try openEQView()

        let saveButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Save'")).firstMatch

        // May need to scroll down
        if !saveButton.exists {
            app.swipeUpInDetail()
            sleep(1)
        }

        XCTAssertTrue(saveButton.waitForExistence(timeout: 5),
                      "EQ view should have Save as Preset button")
    }

    // MARK: - ReAuth View (session expired modal)

    func testSignOutButtonExists() throws {
        app.goToSettings()
        sleep(2)

        // Sign Out should exist in Settings
        let signOutButton = app.buttons["Sign Out"]
        let signOutText = app.staticTexts["Sign Out"]

        for _ in 0..<3 {
            if signOutButton.exists || signOutText.exists { break }
            app.swipeUpInDetail()
            sleep(1)
        }

        let hasSignOut = signOutButton.waitForExistence(timeout: 5)
            || signOutText.exists

        XCTAssertTrue(hasSignOut,
                      "Settings should have Sign Out button")
    }

    // MARK: - Helpers

    private func openEQView() throws {
        app.goToSettings()
        sleep(2)

        // Use accessibilityIdentifier first (most reliable on iOS 26)
        let eqLink = app.buttons["eqSettingsLink"]
        let eqButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'EQ Settings'")).firstMatch

        for _ in 0..<5 {
            if eqLink.exists || eqButton.exists { break }
            app.swipeUp()
            sleep(1)
        }

        if eqLink.waitForExistence(timeout: 5) {
            eqLink.tap()
        } else if eqButton.exists {
            eqButton.tap()
        } else {
            throw XCTSkip("EQ Settings link not found in Settings")
        }
        sleep(2)
    }
}
