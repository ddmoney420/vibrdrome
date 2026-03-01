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

        // Wait for main screen to appear (tab bar or sidebar)
        XCTAssertTrue(app.waitForMainScreen(),
                      "Should navigate to main screen after sign in")
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
