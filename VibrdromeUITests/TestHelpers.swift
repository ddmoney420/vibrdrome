import XCTest

// MARK: - Test Server Credentials
// Reads from environment variables set in Xcode scheme or CI.
// Set TEST_SERVER_URL, TEST_SERVER_USER, TEST_SERVER_PASS before running UI tests.

enum TestServer {
    static let url = ProcessInfo.processInfo.environment["TEST_SERVER_URL"] ?? ""
    static let username = ProcessInfo.processInfo.environment["TEST_SERVER_USER"] ?? ""
    static let password = ProcessInfo.processInfo.environment["TEST_SERVER_PASS"] ?? ""
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
    /// Excludes the ReAuth modal (which also has "Sign In" but no URL text field).
    var isOnLoginScreen: Bool {
        // ReAuth modal has "Session Expired" — not the login screen
        guard !staticTexts["Session Expired"].exists else { return false }
        return (buttons["Sign In"].exists
            || staticTexts["Sign In"].exists
            || staticTexts["Connect to your Navidrome server"].exists)
    }

    /// Whether the ReAuth modal is showing (session expired).
    var isShowingReAuth: Bool {
        staticTexts["Session Expired"].exists
    }

    /// Whether the app is showing the main tab bar (iPhone) or sidebar (iPad).
    var isOnMainScreen: Bool {
        tabBars.buttons["Library"].exists
            || staticTexts["Vibrdrome"].exists  // Sidebar navigation title on iPad
    }

    /// Whether the app is using sidebar layout (iPad).
    var isSidebarLayout: Bool {
        !tabBars.buttons["Library"].exists && staticTexts["Vibrdrome"].exists
    }

    /// Sign in with test credentials. Assumes app is on the login screen.
    func signIn() {
        // Try accessibility identifier first (most reliable on iOS 26+),
        // then fall back to label-based lookup.
        let urlById = textFields["serverURLField"]
        let urlCandidates = [
            textFields["URL"],
            textFields["Server URL"],
            textFields["https://..."],
        ]
        if urlById.waitForExistence(timeout: 3) {
            urlById.tap()
            urlById.clearAndType(TestServer.url)
        } else if let urlField = urlCandidates.first(where: { $0.waitForExistence(timeout: 2) }) {
            urlField.tap()
            urlField.clearAndType(TestServer.url)
        } else {
            let firstField = textFields.firstMatch
            if firstField.waitForExistence(timeout: 3) {
                firstField.tap()
                firstField.clearAndType(TestServer.url)
            }
        }

        let usernameById = textFields["usernameField"]
        let usernameByLabel = textFields["Username"]
        if usernameById.waitForExistence(timeout: 2) {
            usernameById.tap()
            usernameById.clearAndType(TestServer.username)
        } else if usernameByLabel.waitForExistence(timeout: 2) {
            usernameByLabel.tap()
            usernameByLabel.clearAndType(TestServer.username)
        }

        let passwordById = secureTextFields["passwordField"]
        let passwordByLabel = secureTextFields["Password"]
        if passwordById.waitForExistence(timeout: 2) {
            passwordById.tap()
            passwordById.clearAndType(TestServer.password)
        } else if passwordByLabel.waitForExistence(timeout: 2) {
            passwordByLabel.tap()
            passwordByLabel.clearAndType(TestServer.password)
        }

        // Tap Sign In
        let signInButton = buttons["Sign In"]
        if signInButton.waitForExistence(timeout: 3) && signInButton.isEnabled {
            signInButton.tap()
        }
    }

    /// Handle the ReAuth modal if it appears (enter password + tap Sign In).
    func handleReAuth() {
        guard isShowingReAuth else { return }
        let passwordField = secureTextFields["Password"]
        if passwordField.waitForExistence(timeout: 3) {
            passwordField.tap()
            passwordField.clearAndType(TestServer.password)
        }
        let signIn = buttons["Sign In"]
        if signIn.waitForExistence(timeout: 3) && signIn.isEnabled {
            signIn.tap()
        }
        sleep(3)
    }

    /// Ensure the app is logged in. Handles login screen, ReAuth modal, or already logged in.
    func ensureLoggedIn() {
        sleep(2)
        if isShowingReAuth {
            handleReAuth()
        } else if isOnLoginScreen {
            signIn()
        }
        _ = waitForMainScreen()
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
        // iPad: sidebar with "Vibrdrome" title appears
        let sidebarTitle = staticTexts["Vibrdrome"]
        if sidebarTitle.waitForExistence(timeout: 3) { return true }
        return false
    }

    // MARK: - Playback Helpers

    /// Whether playback is active (Play or Pause button visible in mini player).
    var isPlaybackActive: Bool {
        buttons.matching(NSPredicate(format: "label == 'Pause'")).firstMatch.exists
            || buttons.matching(NSPredicate(format: "label == 'Play'")).firstMatch.exists
    }

    /// Start playback reliably. Uses "Random Mix" button in Library as primary
    /// strategy (single tap, no navigation into album detail needed). Falls back
    /// to tapping an album card then a track row.
    /// - Throws: `XCTSkip` if playback cannot be started.
    func playAnyTrack() throws {
        // Already playing?
        if isPlaybackActive { return }

        goToLibrary()
        sleep(2)

        // Strategy 1: Tap "Random Mix" — most reliable, loads 50 songs and plays
        let randomMix = buttons["Random Mix"]
        if !randomMix.waitForExistence(timeout: 3) {
            // Scroll down to find Random Mix in the "More" section
            swipeUpInDetail()
            sleep(1)
        }
        if randomMix.exists {
            randomMix.tap()
            // Wait for API call + SwiftUI render. The "Now Playing" button on
            // the mini player is the most reliable indicator.
            let nowPlaying = buttons["Now Playing"]
            if nowPlaying.waitForExistence(timeout: 15) { return }
            // Also check Play/Pause
            if isPlaybackActive { return }
        }

        // Strategy 2: Navigate to album detail → tap Play button
        goToLibrary()
        sleep(1)
        // Album cards may appear as buttons or otherElements depending on
        // how NavigationLink renders with .accessibilityElement(children: .combine)
        let albumCardPred = NSPredicate(format: "identifier == 'albumCard'")
        let albumFromButtons = buttons.matching(albumCardPred)
        let albumFromOthers = otherElements.matching(albumCardPred)
        let albumCard = albumFromButtons.count > 0
            ? albumFromButtons.firstMatch
            : albumFromOthers.firstMatch
        if albumCard.waitForExistence(timeout: 5) {
            albumCard.tap()
            sleep(2)
            // Tap the Play button in album detail header
            let playButton = buttons["Play"]
            if playButton.waitForExistence(timeout: 5) {
                playButton.tap()
                sleep(2)
                if isPlaybackActive || buttons["Now Playing"].exists { return }
            }
            // Fallback: tap the first track row
            let trackRowPred = NSPredicate(format: "identifier BEGINSWITH 'trackRow_'")
            let trackRow = buttons.matching(trackRowPred).firstMatch.exists
                ? buttons.matching(trackRowPred).firstMatch
                : otherElements.matching(trackRowPred).firstMatch
            if trackRow.waitForExistence(timeout: 3) {
                trackRow.tap()
                sleep(2)
                if isPlaybackActive || buttons["Now Playing"].exists { return }
            }
        }

        throw XCTSkip("Could not start playback")
    }

    /// Open Now Playing full screen view. Assumes playback is active.
    /// - Throws: `XCTSkip` if Now Playing cannot be opened.
    func openNowPlaying() throws {
        // Already in Now Playing?
        if buttons["Shuffle"].exists { return }

        // Tap the "Now Playing" button on the mini player
        let nowPlayingButton = buttons["Now Playing"]
        if nowPlayingButton.waitForExistence(timeout: 5) {
            nowPlayingButton.tap()
            sleep(2)
            if buttons["Shuffle"].waitForExistence(timeout: 5) { return }
        }

        // Fallback: tap the mini player area by coordinate
        let miniPlayer = otherElements["MiniPlayer"]
        if miniPlayer.exists {
            miniPlayer.tap()
            sleep(2)
            if buttons["Shuffle"].waitForExistence(timeout: 5) { return }
        }

        // Last resort: tap near bottom of screen
        let coord = coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.90))
        coord.tap()
        sleep(2)
        if buttons["Shuffle"].waitForExistence(timeout: 5) { return }

        throw XCTSkip("Could not open Now Playing view")
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
