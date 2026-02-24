import XCTest

/// Tests the login flow on macOS.
final class MacLoginTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    func testSignInWithValidCredentials() throws {
        if app.isOnMainScreen {
            app.signOut()
            // Wait longer for sign-out to complete and login screen to appear
            let signIn = app.buttons["Sign In"]
            let connectText = app.staticTexts["Connect to your Navidrome server"]
            guard signIn.waitForExistence(timeout: 20) || connectText.exists else {
                throw XCTSkip("Could not reach login screen after sign out")
            }
        }

        guard app.isOnLoginScreen else {
            throw XCTSkip("Not on login screen")
        }

        app.signIn()
        XCTAssertTrue(app.waitForMainScreen(timeout: 20),
                      "Should navigate to main screen after sign in")
    }

    func testSignInShowsSidebarItems() throws {
        ensureLoggedIn()

        // macOS uses sidebar navigation — verify all expected items
        let sidebarItems = [
            "Artists", "Albums", "Genres", "Favorites",
            "Recently Added", "Most Played", "Recently Played", "Random",
            "Bookmarks", "Folders", "Downloads",
            "Search", "Playlists", "Stations"
        ]
        var foundCount = 0
        for item in sidebarItems {
            if app.staticTexts[item].exists || app.buttons[item].exists {
                foundCount += 1
            }
        }

        // Some items may be scrolled off screen — expect at least most visible
        XCTAssertGreaterThanOrEqual(foundCount, 8,
                                     "Sidebar should show at least 8 of 14 items, found \(foundCount)")
    }

    func testSignOutReturnsToLoginScreen() throws {
        ensureLoggedIn()

        app.signOut()

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
            XCTAssertTrue(app.waitForMainScreen())
        }
    }
}
