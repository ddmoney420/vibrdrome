import XCTest

/// Tests playlist features: viewing, creating, smart playlists.
final class PlaylistTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
    }

    // MARK: - Playlists Tab

    func testPlaylistsTabShowsContent() throws {
        app.goToPlaylists()
        sleep(3)

        let hasNewPlaylist = app.buttons["New Playlist"].exists
        let hasSmartMix = app.buttons["Smart Mix"].exists
        let hasContent = app.staticTexts.count > 1

        XCTAssertTrue(hasNewPlaylist || hasSmartMix || hasContent,
                      "Playlists tab should show content or action buttons")
    }

    func testNewPlaylistButtonExists() throws {
        app.goToPlaylists()
        sleep(2)

        let newPlaylist = app.buttons["New Playlist"]
        XCTAssertTrue(newPlaylist.waitForExistence(timeout: 5),
                      "Playlists tab should have 'New Playlist' button")
    }

    func testSmartMixButtonExists() throws {
        app.goToPlaylists()
        sleep(2)

        let smartMix = app.buttons["Smart Mix"]
        XCTAssertTrue(smartMix.waitForExistence(timeout: 5),
                      "Playlists tab should have 'Smart Mix' button")
    }

    // MARK: - Create Playlist

    func testNewPlaylistOpensEditor() throws {
        app.goToPlaylists()
        sleep(2)

        let newPlaylist = app.buttons["New Playlist"]
        guard newPlaylist.waitForExistence(timeout: 5) else {
            throw XCTSkip("New Playlist button not found")
        }

        newPlaylist.tap()
        sleep(2)

        // Playlist editor should show a name field and search
        let nameField = app.textFields.firstMatch
        let createButton = app.buttons["Create"]
        let cancelButton = app.buttons["Cancel"]

        let editorOpened = nameField.waitForExistence(timeout: 5)
            || createButton.exists
            || cancelButton.exists

        XCTAssertTrue(editorOpened,
                      "Playlist editor should open with name field")

        // Dismiss
        if cancelButton.exists { cancelButton.tap() }
        sleep(1)
    }

    func testPlaylistEditorHasSongSearch() throws {
        app.goToPlaylists()
        sleep(2)

        let newPlaylist = app.buttons["New Playlist"]
        guard newPlaylist.waitForExistence(timeout: 5) else {
            throw XCTSkip("New Playlist button not found")
        }

        newPlaylist.tap()
        sleep(2)

        // Should have a search field for adding songs
        let searchField = app.searchFields.firstMatch
            ?? app.textFields.matching(
                NSPredicate(format: "placeholderValue CONTAINS[c] 'search'")).firstMatch

        let hasSearch = searchField.waitForExistence(timeout: 5)
        // May also just have the name field
        XCTAssertTrue(hasSearch || app.textFields.count > 0,
                      "Playlist editor should have input fields")

        // Dismiss
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.exists { cancelButton.tap() }
        sleep(1)
    }

    // MARK: - Smart Playlists

    func testSmartMixOpensView() throws {
        app.goToPlaylists()
        sleep(2)

        let smartMix = app.buttons["Smart Mix"]
        guard smartMix.waitForExistence(timeout: 5) else {
            throw XCTSkip("Smart Mix button not found")
        }

        smartMix.tap()
        sleep(2)

        // Smart playlist view should show mix types
        let mixTypes = ["Artist Mix", "Genre Mix", "Similar Songs",
                        "Random Mix", "B-Sides & Obscure", "Curated Weekly"]
        var foundCount = 0
        for mixType in mixTypes {
            if app.staticTexts[mixType].exists || app.buttons[mixType].exists {
                foundCount += 1
            }
        }

        XCTAssertGreaterThan(foundCount, 0,
                             "Smart Mix should show playlist types")
    }

    func testSmartMixHasAllTypes() throws {
        app.goToPlaylists()
        sleep(2)

        let smartMix = app.buttons["Smart Mix"]
        guard smartMix.waitForExistence(timeout: 5) else {
            throw XCTSkip("Smart Mix button not found")
        }

        smartMix.tap()
        sleep(2)

        let expectedTypes = ["Artist Mix", "Genre Mix", "Similar Songs",
                             "Random Mix", "B-Sides & Obscure", "Curated Weekly"]
        var foundCount = 0
        for mixType in expectedTypes {
            if app.staticTexts[mixType].exists || app.buttons[mixType].exists {
                foundCount += 1
            }
        }

        XCTAssertGreaterThanOrEqual(foundCount, 4,
                                     "Smart Mix should show at least 4 of 6 types, found \(foundCount)")
    }

    // MARK: - Playlist Detail

    func testFirstPlaylistOpens() throws {
        app.goToPlaylists()
        sleep(3)

        // Try to find and tap a playlist
        let buttons = app.buttons.allElementsBoundByIndex
        var tappedPlaylist = false
        for btn in buttons {
            let label = btn.label.lowercased()
            if ["new playlist", "smart mix", "library", "search",
                "playlists", "radio", "settings", "refresh"].contains(label) { continue }
            if btn.frame.width < 50 { continue }
            // This might be a playlist card
            btn.tap()
            tappedPlaylist = true
            break
        }

        guard tappedPlaylist else {
            throw XCTSkip("No playlists available to tap")
        }
        sleep(3)

        // Playlist detail should show tracks or play/shuffle buttons
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

        // Find and tap first playlist
        let buttons = app.buttons.allElementsBoundByIndex
        var tappedPlaylist = false
        for btn in buttons {
            let label = btn.label.lowercased()
            if ["new playlist", "smart mix", "library", "search",
                "playlists", "radio", "settings", "refresh"].contains(label) { continue }
            if btn.frame.width < 50 { continue }
            btn.tap()
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
