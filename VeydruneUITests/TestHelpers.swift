import XCTest

// MARK: - Test Server Credentials

enum TestServer {
    static let url = "https://***REMOVED***"
    static let username = "dmoney"
    static let password = "***REMOVED***"
}

// MARK: - XCUIApplication Helpers

extension XCUIApplication {

    /// Wait for an element to exist with a timeout.
    @discardableResult
    func waitForElement(
        _ element: XCUIElement,
        timeout: TimeInterval = 10
    ) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// Whether the app is showing the login/server config screen.
    var isOnLoginScreen: Bool {
        buttons["Sign In"].exists
            || staticTexts["Sign In"].exists
            || staticTexts["Connect to your Navidrome server"].exists
    }

    /// Whether the app is showing the main tab bar.
    var isOnMainScreen: Bool {
        tabBars.buttons["Library"].exists
    }

    /// Sign in with test credentials. Assumes app is on the login screen.
    func signIn() {
        let urlField = textFields["URL"].exists
            ? textFields["URL"]
            : textFields["Server URL"]

        // Clear and type URL
        if urlField.waitForExistence(timeout: 5) {
            urlField.tap()
            urlField.clearAndType(TestServer.url)
        }

        let usernameField = textFields["Username"]
        if usernameField.exists {
            usernameField.tap()
            usernameField.clearAndType(TestServer.username)
        }

        let passwordField = secureTextFields["Password"]
        if passwordField.exists {
            passwordField.tap()
            passwordField.clearAndType(TestServer.password)
        }

        // Tap Sign In
        let signInButton = buttons["Sign In"]
        if signInButton.exists && signInButton.isEnabled {
            signInButton.tap()
        }
    }

    /// Sign out from the Settings tab. Assumes app is on the main screen.
    func signOut() {
        tabBars.buttons["Settings"].tap()
        sleep(2)

        // In iOS 26 SwiftUI, a destructive Button with Label may appear as a
        // button or a static text. Try multiple approaches.
        let signOutButton = buttons["Sign Out"]
        let signOutText = staticTexts["Sign Out"]

        // Scroll down to find Sign Out if not visible
        for _ in 0..<3 {
            if signOutButton.exists || signOutText.exists { break }
            swipeUp()
            sleep(1)
        }

        if signOutButton.exists {
            signOutButton.tap()
        } else if signOutText.exists {
            signOutText.tap()
        }

        sleep(1)
        // Confirm the alert
        let confirmButton = alerts.buttons["Sign Out"]
        if confirmButton.waitForExistence(timeout: 5) {
            confirmButton.tap()
        }
        sleep(2) // Wait for transition to login screen
    }

    /// Tap the Library tab.
    func goToLibrary() {
        tabBars.buttons["Library"].tap()
    }

    /// Tap the Search tab.
    func goToSearch() {
        tabBars.buttons["Search"].tap()
    }

    /// Tap the Playlists tab.
    func goToPlaylists() {
        tabBars.buttons["Playlists"].tap()
    }

    /// Tap the Radio tab.
    func goToRadio() {
        tabBars.buttons["Radio"].tap()
    }

    /// Tap the Settings tab.
    func goToSettings() {
        tabBars.buttons["Settings"].tap()
    }
}

// MARK: - XCUIElement Helpers

extension XCUIElement {

    /// Clear the text field and type new text.
    func clearAndType(_ text: String) {
        guard exists else { return }
        tap()
        // Select all existing text
        if let currentValue = value as? String, !currentValue.isEmpty {
            tap() // focus
            press(forDuration: 1.0) // long press to trigger selection
            if menuItems["Select All"].waitForExistence(timeout: 2) {
                menuItems["Select All"].tap()
            }
            typeText(XCUIKeyboardKey.delete.rawValue)
        }
        typeText(text)
    }
}
