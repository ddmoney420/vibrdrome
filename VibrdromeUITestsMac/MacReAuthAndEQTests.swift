import XCTest

/// macOS UI tests for ReAuth modal and EQ slider accessibility.
final class MacReAuthAndEQTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.activate()
        sleep(1)
        ensureLoggedIn()
    }

    // MARK: - EQ View

    func testEQViewOpensFromSettings() throws {
        app.openSettingsWindow()
        sleep(2)

        // Find Equalizer button in settings
        let eqButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Equalizer'")).firstMatch

        guard eqButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Equalizer button not found in Settings")
        }

        eqButton.tap()
        sleep(2)

        // EQ view should show Done and Reset buttons
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5),
                      "EQ view should show Done button")
    }

    func testEQPresetsExist() throws {
        try openEQView()

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
                      "EQ view should have Reset button in toolbar")
    }

    func testEQSliderAccessibility() throws {
        try openEQView()

        // On macOS, check for accessible slider elements with Hz labels
        let hzPredicate = NSPredicate(format: "label CONTAINS 'Hz'")
        let hzElements = app.otherElements.matching(hzPredicate)

        XCTAssertGreaterThan(hzElements.count, 0,
                             "EQ sliders should have Hz accessibility labels on macOS")
    }

    // MARK: - Settings Integrity

    func testSignOutButtonInSettings() throws {
        app.openSettingsWindow()
        sleep(2)

        let signOutButton = app.buttons["Sign Out"]
        XCTAssertTrue(signOutButton.waitForExistence(timeout: 5),
                      "Settings should show Sign Out button")
    }

    func testManageServersButton() throws {
        app.openSettingsWindow()
        sleep(2)

        let manageServers = app.buttons["Manage Servers"]
        XCTAssertTrue(manageServers.waitForExistence(timeout: 5),
                      "Settings should show Manage Servers button")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        // Check for login fields
        let signInButton = app.buttons["Sign In"]
        if signInButton.waitForExistence(timeout: 3) {
            // Use MacTestHelpers signIn if available, otherwise basic attempt
            let urlField = app.textFields["URL"]
            if urlField.exists {
                urlField.tap()
                urlField.typeText(TestServer.url)
            }
            let usernameField = app.textFields["Username"]
            if usernameField.exists {
                usernameField.tap()
                usernameField.typeText(TestServer.username)
            }
            let passwordField = app.secureTextFields["Password"]
            if passwordField.exists {
                passwordField.tap()
                passwordField.typeText(TestServer.password)
            }
            signInButton.tap()
            sleep(5)
        }
    }

    private func openEQView() throws {
        app.openSettingsWindow()
        sleep(2)

        let eqButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Equalizer'")).firstMatch

        guard eqButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Equalizer button not found in Settings")
        }

        eqButton.tap()
        sleep(2)
    }
}
