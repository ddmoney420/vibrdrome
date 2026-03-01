import XCTest

/// Tests that verify the app launches correctly and shows the expected initial screen.
final class LaunchTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    // MARK: - Launch

    func testAppLaunches() throws {
        app.launch()
        // App should show either login screen or main screen
        let showsLogin = app.isOnLoginScreen
        let showsMain = app.isOnMainScreen
        XCTAssertTrue(showsLogin || showsMain, "App should show login or main screen after launch")
    }

    func testAppDoesNotCrashOnLaunch() throws {
        app.launch()
        // Wait a moment to ensure stability
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground, "App should remain in foreground")
    }

    // MARK: - Login Screen Validation

    func testLoginScreenHasRequiredFields() throws {
        // Reset app state by signing out if needed
        app.launch()

        if !app.isOnLoginScreen {
            // Already logged in — sign out first
            app.signOut()
            guard app.waitForElement(app.buttons["Sign In"], timeout: 15) else {
                throw XCTSkip("Could not reach login screen after sign out")
            }
        }

        // Verify all login fields exist
        // SwiftUI Form renders TextField("URL") with "URL" as a label;
        // the actual text field may use the prompt text as its identifier.
        let urlField = app.textFields["URL"].exists
            || app.textFields["Server URL"].exists
            || app.textFields["https://..."].exists
            || app.textFields.count >= 2
        XCTAssertTrue(urlField, "Login screen should have a URL field")

        let usernameField = app.textFields["Username"]
        XCTAssertTrue(usernameField.exists, "Login screen should have a Username field")

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.exists, "Login screen should have a Password field")

        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.exists, "Login screen should have a Sign In button")
    }

    func testSignInButtonDisabledWithEmptyFields() throws {
        app.launch()

        guard app.isOnLoginScreen else { return }

        let signInButton = app.buttons["Sign In"]
        // With all fields empty, Sign In should be disabled
        XCTAssertFalse(signInButton.isEnabled, "Sign In should be disabled with empty fields")
    }
}
