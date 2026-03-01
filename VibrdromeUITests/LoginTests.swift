import XCTest

/// Tests the login flow with real server credentials.
final class LoginTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureForTesting()
        app.launch()
    }

    // MARK: - Sign In Flow

    func testSignInWithValidCredentials() throws {
        // Auto-login should have already signed us in.
        // Verify by checking for the main screen.
        XCTAssertTrue(app.waitForMainScreen(timeout: 30),
                      "Should navigate to main screen after auto-login")
    }

    func testSignInShowsAllTabs() throws {
        app.ensureLoggedIn()

        if app.isSidebarLayout {
            // iPad: verify key sidebar items exist
            let sidebarItems = ["Artists", "Search", "Playlists", "Stations", "Settings"]
            for item in sidebarItems {
                let found = app.staticTexts[item].exists || app.buttons[item].exists
                XCTAssertTrue(found,
                              "Sidebar should have '\(item)' item")
            }
        } else {
            // iPhone: verify all 5 tabs exist
            let tabs = ["Library", "Search", "Playlists", "Radio", "Settings"]
            for tab in tabs {
                XCTAssertTrue(app.tabBars.buttons[tab].exists,
                              "Tab bar should have '\(tab)' tab")
            }
        }
    }

    func testSignOutReturnsToLoginScreen() throws {
        app.ensureLoggedIn()

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

}
