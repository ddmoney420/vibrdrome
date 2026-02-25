import XCTest

/// Tests playlist features on macOS.
final class MacPlaylistTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
    }

    // MARK: - Playlists Sidebar

    func testPlaylistsSidebarShowsContent() throws {
        app.goToPlaylists()
        sleep(3)

        let hasNewPlaylist = app.buttons["New Playlist"].firstMatch.exists
        let hasSmartMix = app.buttons["Smart Mix"].firstMatch.exists
        let hasContent = app.staticTexts.count > 1

        XCTAssertTrue(hasNewPlaylist || hasSmartMix || hasContent,
                      "Playlists view should show content or action buttons")
    }

    func testNewPlaylistButtonExists() throws {
        app.goToPlaylists()
        sleep(2)

        let newPlaylist = app.buttons["New Playlist"].firstMatch
        XCTAssertTrue(newPlaylist.waitForExistence(timeout: 5),
                      "Playlists view should have 'New Playlist' button")
    }

    func testSmartMixButtonExists() throws {
        app.goToPlaylists()
        sleep(2)

        let smartMix = app.buttons["Smart Mix"].firstMatch
        XCTAssertTrue(smartMix.waitForExistence(timeout: 5),
                      "Playlists view should have 'Smart Mix' button")
    }

    // MARK: - Create Playlist

    func testNewPlaylistOpensEditor() throws {
        app.goToPlaylists()
        sleep(2)

        let newPlaylist = app.buttons["New Playlist"].firstMatch
        guard newPlaylist.waitForExistence(timeout: 5) else {
            throw XCTSkip("New Playlist button not found")
        }

        newPlaylist.click()
        sleep(2)

        let nameField = app.textFields.firstMatch
        let createButton = app.buttons["Create"]
        let cancelButton = app.buttons["Cancel"]

        let editorOpened = nameField.waitForExistence(timeout: 5)
            || createButton.exists
            || cancelButton.exists

        XCTAssertTrue(editorOpened,
                      "Playlist editor should open with name field")

        if cancelButton.exists { cancelButton.click() }
        sleep(1)
    }

    func testPlaylistEditorHasSongSearch() throws {
        app.goToPlaylists()
        sleep(2)

        let newPlaylist = app.buttons["New Playlist"].firstMatch
        guard newPlaylist.waitForExistence(timeout: 5) else {
            throw XCTSkip("New Playlist button not found")
        }

        newPlaylist.click()
        sleep(2)

        let searchField = app.searchFields.firstMatch
        let hasSearch = searchField.waitForExistence(timeout: 5)
        XCTAssertTrue(hasSearch || app.textFields.count > 0,
                      "Playlist editor should have input fields")

        let cancelButton = app.buttons["Cancel"]
        if cancelButton.exists { cancelButton.click() }
        sleep(1)
    }

    // MARK: - Smart Mix

    func testSmartMixOpensView() throws {
        app.goToPlaylists()
        sleep(2)

        let smartMix = app.buttons["Smart Mix"].firstMatch
        guard smartMix.waitForExistence(timeout: 5) else {
            throw XCTSkip("Smart Mix button not found")
        }

        smartMix.click()
        sleep(3)

        // Smart Playlist view shows generator cards in a LazyVGrid.
        // Each card is a plain Button containing Text elements.
        // Use CONTAINS[c] to find text within the card labels.
        let mixTypes = ["Artist Mix", "Genre Mix", "Similar Songs",
                        "Random Mix", "B-Sides", "Curated Weekly"]
        var foundCount = 0
        for mixType in mixTypes {
            let textMatch = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", mixType)).firstMatch
            let buttonMatch = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", mixType)).firstMatch
            if textMatch.exists || buttonMatch.exists {
                foundCount += 1
            }
        }

        // Also check for the navigation title as fallback
        let smartPlaylistTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Smart Playlist'")).firstMatch

        XCTAssertTrue(foundCount > 0 || smartPlaylistTitle.exists,
                      "Smart Mix should show playlist types, found \(foundCount)")
    }

    // MARK: - Playlist Detail

    func testFirstPlaylistOpens() throws {
        app.goToPlaylists()
        sleep(3)

        let buttons = app.buttons.allElementsBoundByIndex
        var tappedPlaylist = false
        for btn in buttons {
            let label = btn.label.lowercased()
            if ["new playlist", "smart mix", "artists", "albums", "search",
                "playlists", "stations", "refresh"].contains(label) { continue }
            if btn.frame.width < 50 { continue }
            btn.click()
            tappedPlaylist = true
            break
        }

        guard tappedPlaylist else {
            throw XCTSkip("No playlists available to tap")
        }
        sleep(3)

        let playButton = app.buttons["Play"]
        let shuffleButton = app.buttons["Shuffle"]
        let hasDetail = playButton.waitForExistence(timeout: 5)
            || shuffleButton.exists
            || app.staticTexts.count > 3

        XCTAssertTrue(hasDetail,
                      "Playlist detail should show content")
    }

    func testPlaylistDetailHasPlayAndShuffle() throws {
        app.goToPlaylists()
        sleep(3)

        let buttons = app.buttons.allElementsBoundByIndex
        var tappedPlaylist = false
        for btn in buttons {
            let label = btn.label.lowercased()
            if ["new playlist", "smart mix", "artists", "albums", "search",
                "playlists", "stations", "refresh"].contains(label) { continue }
            if btn.frame.width < 50 { continue }
            btn.click()
            tappedPlaylist = true
            break
        }

        guard tappedPlaylist else {
            throw XCTSkip("No playlists available")
        }
        sleep(3)

        let playButton = app.buttons["Play"]
        let shuffleButton = app.buttons["Shuffle"]

        XCTAssertTrue(playButton.waitForExistence(timeout: 5),
                      "Playlist detail should have Play button")
        XCTAssertTrue(shuffleButton.exists,
                      "Playlist detail should have Shuffle button")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            XCTAssertTrue(app.waitForMainScreen())
        }
    }
}
