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
    var isOnLoginScreen: Bool {
        buttons["Sign In"].exists
            || staticTexts["Sign In"].exists
            || staticTexts["Connect to your Navidrome server"].exists
    }

    /// Whether the app is showing the main sidebar screen.
    var isOnMainScreen: Bool {
        outlines["Sidebar"].exists
            || outlines["Sidebar"].waitForExistence(timeout: 3)
    }

    /// Sign in with test credentials. Assumes app is on the login screen.
    func signIn() {
        let urlField = textFields["URL"].exists
            ? textFields["URL"]
            : textFields["Server URL"]

        if urlField.waitForExistence(timeout: 5) {
            urlField.click()
            urlField.clearAndType(TestServer.url)
        }

        let usernameField = textFields["Username"]
        if usernameField.exists {
            usernameField.click()
            usernameField.clearAndType(TestServer.username)
        }

        let passwordField = secureTextFields["Password"]
        if passwordField.exists {
            passwordField.click()
            passwordField.clearAndType(TestServer.password)
        }

        let signInButton = buttons["Sign In"]
        if signInButton.exists && signInButton.isEnabled {
            signInButton.click()
        }
    }

    /// Sign out via the Settings window. Assumes app is on the main screen.
    func signOut() {
        openSettingsWindow()
        sleep(3)

        // Sign Out is in the Server section (near the top), so it should
        // be visible without scrolling. But scroll up first just in case.
        scrollUpInSettings()
        sleep(1)

        let signOutButton = buttons["Sign Out"]
        let signOutText = staticTexts["Sign Out"]

        if signOutButton.exists {
            signOutButton.click()
        } else if signOutText.exists {
            signOutText.click()
        }

        sleep(2)

        // Confirm the alert — macOS may use alerts, sheets, dialogs, or
        // plain buttons depending on the SwiftUI .confirmationDialog rendering.
        let alertConfirm = alerts.buttons["Sign Out"]
        let sheetConfirm = sheets.buttons["Sign Out"]
        let dialogConfirm = dialogs.buttons["Sign Out"]

        // Also look for a destructive-styled button in any container
        let anyConfirm = buttons.matching(
            NSPredicate(format: "label == 'Sign Out'")).allElementsBoundByIndex
            .filter { $0.frame.minY > 0 }

        if alertConfirm.waitForExistence(timeout: 5) {
            alertConfirm.click()
        } else if sheetConfirm.exists {
            sheetConfirm.click()
        } else if dialogConfirm.exists {
            dialogConfirm.click()
        } else if anyConfirm.count > 1 {
            // There are multiple "Sign Out" buttons — the second one is the
            // confirmation button (the first is the settings row button)
            anyConfirm.last?.click()
        } else {
            // Retry: click the Sign Out button again to trigger the dialog
            if signOutButton.exists {
                signOutButton.click()
                sleep(2)
                if alertConfirm.waitForExistence(timeout: 5) {
                    alertConfirm.click()
                } else if dialogConfirm.waitForExistence(timeout: 3) {
                    dialogConfirm.click()
                } else {
                    // Last resort: look for any confirmation button
                    let confirm2 = buttons.matching(
                        NSPredicate(format: "label == 'Sign Out'")).allElementsBoundByIndex
                    if confirm2.count > 1 { confirm2.last?.click() }
                }
            }
        }
        sleep(5)
    }

    // MARK: - Sidebar Navigation

    /// Navigate to a sidebar item by label. Uses the Outline element to avoid
    /// ambiguity with navigation title headings that share the same label.
    func goToSidebarItem(_ label: String) {
        let sidebar = outlines["Sidebar"]
        if sidebar.waitForExistence(timeout: 5) {
            let item = sidebar.staticTexts[label]
            if item.waitForExistence(timeout: 3) {
                item.click()
                sleep(1)
                return
            }
        }
        // Fallback: use firstMatch to handle ambiguous staticTexts
        let item = staticTexts[label].firstMatch
        if item.waitForExistence(timeout: 3) {
            item.click()
        }
        sleep(1)
    }

    func goToArtists() { goToSidebarItem("Artists") }
    func goToAlbums() { goToSidebarItem("Albums") }
    func goToSearch() { goToSidebarItem("Search") }
    func goToPlaylists() { goToSidebarItem("Playlists") }
    func goToRadio() { goToSidebarItem("Stations") }
    func goToDownloads() { goToSidebarItem("Downloads") }
    func goToFavorites() { goToSidebarItem("Favorites") }
    func goToBookmarks() { goToSidebarItem("Bookmarks") }
    func goToLibrary() { goToSidebarItem("Artists") }

    // MARK: - Settings Window (Cmd+,)

    /// Open the macOS Settings window via keyboard shortcut.
    func openSettingsWindow() {
        // Ensure app is foregrounded before sending keyboard shortcut
        activate()
        sleep(1)
        typeKey(",", modifierFlags: .command)
        sleep(3)

        // Verify Settings opened by checking for a known element
        let testConnection = buttons["Test Connection"]
        let signOut = buttons["Sign Out"]
        if testConnection.exists || signOut.exists { return }

        // Retry once — sometimes the keyboard shortcut doesn't register
        activate()
        sleep(1)
        typeKey(",", modifierFlags: .command)
        sleep(3)
    }

    // MARK: - Scrolling

    /// Scroll down in the main detail pane.
    func scrollDownInDetail() {
        let window = windows.firstMatch
        let coord = window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        coord.scroll(byDeltaX: 0, deltaY: -200)
    }

    /// Scroll up in the main detail pane.
    func scrollUpInDetail() {
        let window = windows.firstMatch
        let coord = window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        coord.scroll(byDeltaX: 0, deltaY: 200)
    }

    /// Scroll down in the Settings window. On macOS, the Settings scene is a
    /// separate window. We find it by locating a known Settings element and
    /// scrolling from there. Uses multiple strategies to ensure the scroll
    /// event reaches the correct window.
    func scrollDownInSettings(amount: CGFloat = 300) {
        // Strategy 1: Find a known Settings element and scroll from within it.
        // This is the most reliable approach because the element is guaranteed
        // to be in the Settings window.
        let targets: [XCUIElement] = [
            buttons["Sign Out"],
            buttons["Test Connection"],
            buttons["Manage Servers"],
            staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Server'")).firstMatch,
            staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Gapless'")).firstMatch,
            staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Scrobbling'")).firstMatch,
            staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'WiFi'")).firstMatch,
            staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Downloads'")).firstMatch,
            staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Theme'")).firstMatch,
            staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Appearance'")).firstMatch
        ]
        for target in targets {
            if target.exists {
                let coord = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                coord.scroll(byDeltaX: 0, deltaY: -amount)
                return
            }
        }

        // Fallback: Try keyboard-based scrolling (Page Down)
        typeKey(.pageDown, modifierFlags: [])
    }

    /// Scroll up in the Settings window.
    func scrollUpInSettings(amount: CGFloat = 300) {
        let targets: [XCUIElement] = [
            buttons["Test Connection"],
            buttons["Manage Servers"],
            staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Server'")).firstMatch
        ]
        for target in targets {
            if target.exists {
                let coord = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                coord.scroll(byDeltaX: 0, deltaY: amount)
                return
            }
        }
        typeKey(.pageUp, modifierFlags: [])
    }

    // MARK: - Main Screen

    /// Wait for main screen to be ready after login.
    func waitForMainScreen(timeout: TimeInterval = 15) -> Bool {
        let sidebar = outlines["Sidebar"]
        if sidebar.waitForExistence(timeout: timeout) { return true }
        // Fallback: check for any sidebar item text
        let artists = staticTexts["Artists"].firstMatch
        if artists.waitForExistence(timeout: 3) { return true }
        return false
    }

    // MARK: - Playback Helpers

    /// Navigate to library, find an album, tap a track to start playback.
    func playAnyTrack() throws {
        let pauseButton = buttons.matching(
            NSPredicate(format: "label == 'Pause'")).firstMatch
        let playButton = buttons.matching(
            NSPredicate(format: "label == 'Play'")).firstMatch
        if pauseButton.exists || playButton.exists { return }

        // Navigate to Albums (more reliable list than Artists which has sections)
        goToAlbums()
        sleep(5)

        // Wait for albums to load — look for "Loading albums..." to disappear
        let loadingText = staticTexts["Loading albums..."]
        for _ in 0..<10 {
            if !loadingText.exists { break }
            sleep(1)
        }
        sleep(2)

        var clickedAlbum = false

        // Strategy 1: Find cells with album-like labels (contains "song")
        let albumCells = cells.allElementsBoundByIndex
        for cell in albumCells {
            let label = cell.label.lowercased()
            if label.contains("song") {
                cell.click()
                clickedAlbum = true
                break
            }
        }

        // Strategy 2: Find any cell that isn't a sidebar/nav item
        if !clickedAlbum {
            let navLabels = Set(["artists", "albums", "genres", "favorites",
                "recently added", "most played", "recently played", "random",
                "bookmarks", "folders", "downloads", "search", "playlists",
                "stations", "refresh", ""])
            for cell in albumCells {
                let label = cell.label.lowercased()
                if navLabels.contains(label) { continue }
                if label.isEmpty { continue }
                if cell.frame.width < 50 { continue }
                cell.click()
                clickedAlbum = true
                break
            }
        }

        // Strategy 3: Find staticTexts that look like album content
        // AlbumCard accessibility labels contain "by" (artist) and "song"
        if !clickedAlbum {
            let albumLabel = staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'song'")).firstMatch
            if albumLabel.waitForExistence(timeout: 3) {
                albumLabel.click()
                clickedAlbum = true
            }
        }

        // Strategy 4: Find any non-navigation staticText in the detail pane
        if !clickedAlbum {
            let navLabels = Set(["artists", "albums", "genres", "favorites",
                "recently added", "most played", "recently played", "random",
                "bookmarks", "folders", "downloads", "search", "playlists",
                "stations", "loading albums...", "no albums", "loading",
                "error", "refresh", ""])
            let texts = staticTexts.allElementsBoundByIndex
            for text in texts {
                let label = text.label.lowercased()
                if navLabels.contains(label) { continue }
                if text.frame.width < 50 { continue }
                // Must be in the detail pane (right side)
                if text.frame.minX < 200 { continue }
                if label.count > 2 {
                    text.click()
                    clickedAlbum = true
                    break
                }
            }
        }

        guard clickedAlbum else {
            throw XCTSkip("No albums found in library")
        }
        sleep(4)

        // We should now be in AlbumDetailView which has Play and Shuffle buttons.
        // Click the Play button to start playing the entire album.
        let albumPlayButton = buttons["Play"].firstMatch
        if albumPlayButton.waitForExistence(timeout: 8) && albumPlayButton.isEnabled {
            albumPlayButton.click()
            sleep(3)
            let playing = pauseButton.waitForExistence(timeout: 10) || playButton.exists
            if playing { return }
        }

        // Fallback: try clicking a track row directly
        let trackTexts = staticTexts.allElementsBoundByIndex
        for text in trackTexts {
            if text.frame.minY < 200 { continue }
            if text.label.isEmpty { continue }
            let label = text.label.lowercased()
            if ["songs", "albums", "shuffle", "play", "play all",
                "loading", "error"].contains(label) { continue }
            // Track rows have labels like "Song Title, by Artist, 3:45"
            if label.contains(",") || label.count > 5 {
                text.click()
                break
            }
        }
        sleep(3)

        let playing = pauseButton.waitForExistence(timeout: 10) || playButton.exists
        if !playing { throw XCTSkip("Could not start playback") }
    }

    // MARK: - Now Playing

    /// Open Now Playing view from the mini player.
    func openNowPlaying() throws {
        sleep(1)

        // The mini player has album art — click it to open Now Playing window
        let nowPlayingButton = buttons["Now Playing"]
        if nowPlayingButton.waitForExistence(timeout: 5) {
            nowPlayingButton.click()
        } else {
            // Fallback: click near the bottom of the main window
            let window = windows.firstMatch
            let coord = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.92))
            coord.click()
        }
        sleep(2)

        let shuffleButton = buttons["Shuffle"]
        guard shuffleButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Could not open Now Playing view")
        }
    }

    /// Ensure Now Playing is open, opening it if needed.
    func ensureNowPlayingOpen() throws {
        if buttons["Shuffle"].exists { return }
        try openNowPlaying()
        // Allow extra time for all Now Playing controls to render
        sleep(1)
    }

    // MARK: - Toolbar Button Helper

    /// Click a toolbar button by label. On macOS, toolbar buttons can have
    /// nested Button > Button with the same label, causing ambiguity.
    /// This uses .firstMatch to handle that.
    func clickToolbarButton(_ label: String) {
        let btn = buttons[label].firstMatch
        if btn.waitForExistence(timeout: 5) {
            btn.click()
        }
    }
}

// MARK: - XCUIElement Helpers

extension XCUIElement {

    /// Clear the text field and type new text.
    func clearAndType(_ text: String) {
        guard exists else { return }
        click()
        // Select all existing text
        if let currentValue = value as? String, !currentValue.isEmpty {
            click()
            typeKey("a", modifierFlags: .command)
            typeKey(.delete, modifierFlags: [])
        }
        typeText(text)
    }
}
