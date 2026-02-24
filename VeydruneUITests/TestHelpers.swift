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

    /// Whether the app is showing the main tab bar (iPhone) or sidebar (iPad).
    var isOnMainScreen: Bool {
        tabBars.buttons["Library"].exists
            || staticTexts["Veydrune"].exists  // Sidebar navigation title on iPad
    }

    /// Whether the app is using sidebar layout (iPad).
    var isSidebarLayout: Bool {
        !tabBars.buttons["Library"].exists && staticTexts["Veydrune"].exists
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
        goToSettings()
        sleep(3)

        // In iOS 26 SwiftUI, a destructive Button with Label may appear as a
        // button or a static text. Try multiple approaches.
        let signOutButton = buttons["Sign Out"]
        let signOutText = staticTexts["Sign Out"]

        // Scroll down to find Sign Out if not visible
        for _ in 0..<3 {
            if signOutButton.exists || signOutText.exists { break }
            swipeUpInDetail()
            sleep(1)
        }

        if signOutButton.exists {
            signOutButton.tap()
        } else if signOutText.exists {
            signOutText.tap()
        }

        sleep(2)
        // Confirm the alert — try both alerts and sheets (iPad may use either)
        let alertConfirm = alerts.buttons["Sign Out"]
        let sheetConfirm = sheets.buttons["Sign Out"]
        if alertConfirm.waitForExistence(timeout: 5) {
            alertConfirm.tap()
        } else if sheetConfirm.exists {
            sheetConfirm.tap()
        } else {
            // Retry: tap Sign Out again in case first tap didn't register
            if signOutButton.exists {
                signOutButton.tap()
                sleep(1)
                if alertConfirm.waitForExistence(timeout: 5) {
                    alertConfirm.tap()
                }
            }
        }
        sleep(3) // Wait for transition to login screen
    }

    // MARK: - Navigation (supports both TabView on iPhone and Sidebar on iPad)

    /// Navigate to a sidebar item by label. Used on iPad/macOS sidebar layout.
    private func tapSidebarItem(_ label: String) {
        // On iPad, NavigationSplitView sidebar renders as a CollectionView
        // with accessibility label "Sidebar". Cells near the bottom may report
        // hittable=true but fail cell.tap() with hit point {-1,-1}.
        // Use coordinate-based tap at the cell's center instead.

        let sidebar = collectionViews["Sidebar"]

        // Toggle sidebar open if collapsed
        if !sidebar.waitForExistence(timeout: 3) {
            let toggleSidebar = buttons["ToggleSidebar"]
            if toggleSidebar.exists {
                toggleSidebar.tap()
                sleep(1)
            }
        }

        guard sidebar.exists else { return }

        // A small drag ensures lazy-loaded cells at the bottom are populated
        let sf = sidebar.frame
        let dragStart = coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: sf.midX, dy: sf.maxY - 100))
        let dragEnd = coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: sf.midX, dy: sf.maxY - 200))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        sleep(1)

        // Find cell by iterating sidebar cells
        let cells = sidebar.cells.allElementsBoundByIndex
        guard let cell = cells.first(where: { $0.staticTexts[label].exists }) else {
            // Retry after a longer wait
            sleep(2)
            let cells2 = sidebar.cells.allElementsBoundByIndex
            if let cell2 = cells2.first(where: { $0.staticTexts[label].exists }) {
                let tapCoord = coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: cell2.frame.midX, dy: cell2.frame.midY))
                tapCoord.tap()
                sleep(1)
            }
            return
        }

        // Use coordinate-based tap to bypass XCUITest scroll-to-visible issues
        let tapCoord = coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: cell.frame.midX, dy: cell.frame.midY))
        tapCoord.tap()
        sleep(1)
    }

    /// Tap the Library tab (iPhone) or Artists sidebar item (iPad).
    func goToLibrary() {
        if isSidebarLayout {
            tapSidebarItem("Artists")
        } else {
            tabBars.buttons["Library"].tap()
        }
    }

    /// Tap the Search tab (iPhone) or Search sidebar item (iPad).
    func goToSearch() {
        if isSidebarLayout {
            tapSidebarItem("Search")
        } else {
            tabBars.buttons["Search"].tap()
        }
    }

    /// Tap the Playlists tab (iPhone) or Playlists sidebar item (iPad).
    func goToPlaylists() {
        if isSidebarLayout {
            tapSidebarItem("Playlists")
        } else {
            tabBars.buttons["Playlists"].tap()
        }
    }

    /// Tap the Radio tab (iPhone) or Stations sidebar item (iPad).
    func goToRadio() {
        if isSidebarLayout {
            tapSidebarItem("Stations")
        } else {
            tabBars.buttons["Radio"].tap()
        }
    }

    /// Tap the Settings tab (iPhone) or Settings sidebar item (iPad).
    func goToSettings() {
        if isSidebarLayout {
            tapSidebarItem("Settings")
        } else {
            tabBars.buttons["Settings"].tap()
        }
    }

    /// Swipe up in the detail area. On iPad sidebar layout, targets the right
    /// side of the screen so the swipe doesn't hit the sidebar.
    func swipeUpInDetail() {
        if isSidebarLayout {
            // Swipe on the right 2/3 of the screen to target the detail pane
            let coord = coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6))
            let dest = coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3))
            coord.press(forDuration: 0.05, thenDragTo: dest)
        } else {
            swipeUp()
        }
    }

    /// Wait for main screen to be ready after login (works on both iPhone and iPad).
    func waitForMainScreen(timeout: TimeInterval = 15) -> Bool {
        // iPhone: tab bar appears
        let libraryTab = tabBars.buttons["Library"]
        if libraryTab.waitForExistence(timeout: timeout) { return true }
        // iPad: sidebar with "Veydrune" title appears
        let sidebarTitle = staticTexts["Veydrune"]
        if sidebarTitle.waitForExistence(timeout: 3) { return true }
        return false
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
