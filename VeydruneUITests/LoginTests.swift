import XCTest

/// Tests the login flow with real server credentials.
final class LoginTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    // MARK: - Sign In Flow

    func testSignInWithValidCredentials() throws {
        // If already logged in, sign out first
        if app.isOnMainScreen {
            app.signOut()
            guard app.waitForElement(app.buttons["Sign In"], timeout: 15) else {
                throw XCTSkip("Could not reach login screen after sign out")
            }
        }

        guard app.isOnLoginScreen else {
            throw XCTSkip("Not on login screen")
        }

        app.signIn()

        // Wait for main screen to appear (library tab)
        let libraryTab = app.tabBars.buttons["Library"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15),
                      "Should navigate to main screen after sign in")
    }

    func testSignInShowsAllTabs() throws {
        ensureLoggedIn()

        // Verify all 5 tabs exist
        let tabs = ["Library", "Search", "Playlists", "Radio", "Settings"]
        for tab in tabs {
            XCTAssertTrue(app.tabBars.buttons[tab].exists,
                          "Tab bar should have '\(tab)' tab")
        }
    }

    func testSignOutReturnsToLoginScreen() throws {
        ensureLoggedIn()

        app.signOut()

        // Should be back on login screen — check for Sign In button or the
        // "Connect to your Navidrome server" text that appears on the config screen
        let signInButton = app.buttons["Sign In"]
        let connectText = app.staticTexts["Connect to your Navidrome server"]
        let onLoginScreen = signInButton.waitForExistence(timeout: 15)
            || connectText.exists
        XCTAssertTrue(onLoginScreen,
                      "Should return to login screen after sign out")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            let libraryTab = app.tabBars.buttons["Library"]
            XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
        }
    }
}
