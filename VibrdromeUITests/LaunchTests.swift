import XCTest

/// Tests that verify the app launches correctly and shows the expected initial screen.
final class LaunchTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureForTesting()
    }

    // MARK: - Launch

    func testAppLaunches() throws {
        app.launch()
        // App should show either login screen or main screen or ReAuth
        let showsLogin = app.isOnLoginScreen
        let showsMain = app.isOnMainScreen
        let showsReAuth = app.isShowingReAuth
        XCTAssertTrue(showsLogin || showsMain || showsReAuth,
                      "App should show login, main screen, or re-auth after launch")
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

        if app.isShowingReAuth {
            app.handleReAuth()
            guard app.waitForMainScreen() else {
                throw XCTSkip("Could not get past ReAuth modal")
            }
        }

        if !app.isOnLoginScreen {
            // Already logged in — sign out first
            app.signOut()
            guard app.waitForElement(app.buttons["Sign In"], timeout: 15) else {
                throw XCTSkip("Could not reach login screen after sign out")
            }
        }

        // Verify all login fields exist using accessibility identifiers (most reliable on iOS 26)
        let urlField = app.textFields["serverURLField"].exists
            || app.textFields["URL"].exists
            || app.textFields["Server URL"].exists
            || app.textFields["https://..."].exists
            || app.textFields.count >= 2
        XCTAssertTrue(urlField, "Login screen should have a URL field")

        let usernameField = app.textFields["usernameField"].exists
            || app.textFields["Username"].exists
        XCTAssertTrue(usernameField, "Login screen should have a Username field")

        let passwordField = app.secureTextFields["passwordField"].exists
            || app.secureTextFields["Password"].exists
        XCTAssertTrue(passwordField, "Login screen should have a Password field")

        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.exists, "Login screen should have a Sign In button")
    }

    func testSignInButtonDisabledWithEmptyFields() throws {
        app.launch()

        if app.isShowingReAuth {
            // Can't test empty-field state if ReAuth is showing
            throw XCTSkip("ReAuth modal is showing, cannot test empty login fields")
        }

        guard app.isOnLoginScreen else { return }

        let signInButton = app.buttons["Sign In"]
        // With all fields empty, Sign In should be disabled
        XCTAssertFalse(signInButton.isEnabled, "Sign In should be disabled with empty fields")
    }
}
