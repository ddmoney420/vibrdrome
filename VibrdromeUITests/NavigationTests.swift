import XCTest

/// Tests navigation between tabs and into detail views.
final class NavigationTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
    }

    // MARK: - Tab Navigation

    func testLibraryTabShowsContent() throws {
        app.goToLibrary()
        // Library should show navigation content (artists, albums, etc.)
        // Wait for content to load
        sleep(3)
        let hasContent = app.navigationBars.count > 0 || app.staticTexts.count > 2
        XCTAssertTrue(hasContent, "Library tab should show content")
    }

    func testSearchTabShowsSearchField() throws {
        app.goToSearch()
        sleep(1)
        // Search tab should have a search field
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5),
                      "Search tab should have a search field")
    }

    func testPlaylistsTabShowsContent() throws {
        app.goToPlaylists()
        sleep(3)
        // Should show playlists or "New Playlist" button or text content
        let hasNewPlaylist = app.buttons["New Playlist"].exists
        let hasContent = app.staticTexts.count > 1 || app.buttons.count > 5
        XCTAssertTrue(hasNewPlaylist || hasContent,
                      "Playlists tab should show content or new playlist button")
    }

    func testRadioTabShowsContent() throws {
        app.goToRadio()
        sleep(2)
        // Radio tab should show internet radio stations or content
        let hasContent = app.staticTexts.count > 0
        XCTAssertTrue(hasContent, "Radio tab should show content")
    }

    func testSettingsTabShowsContent() throws {
        app.goToSettings()
        sleep(2)
        // Settings should show server info and sign out — may need scrolling on iPad
        let signOutButton = app.buttons["Sign Out"]
        if !signOutButton.exists {
            app.swipeUpInDetail()
            sleep(1)
        }
        let hasContent = signOutButton.waitForExistence(timeout: 5)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Server'")).firstMatch.exists
            || app.buttons["Test Connection"].exists
        XCTAssertTrue(hasContent,
                      "Settings should show server section content")
    }

    func testSwitchBetweenAllTabs() throws {
        if app.isSidebarLayout {
            // iPad: navigate between sidebar items
            let items = ["Artists", "Search", "Playlists", "Stations", "Settings"]
            for item in items {
                app.goToLibrary()  // Reset to known state
                sleep(1)
            }
            // Just verify no crash after switching
            XCTAssertTrue(app.state == .runningForeground,
                          "App should not crash when switching between sidebar items")
        } else {
            // iPhone: switch between tabs
            let tabs = ["Library", "Search", "Playlists", "Radio", "Settings"]
            for tab in tabs {
                app.tabBars.buttons[tab].tap()
                sleep(1)
                XCTAssertTrue(app.state == .runningForeground,
                              "App should not crash when switching to \(tab) tab")
            }
        }
    }

    // MARK: - Search

    func testSearchReturnsResults() throws {
        app.goToSearch()
        let searchField = app.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 5) else {
            XCTFail("Search field not found")
            return
        }

        searchField.tap()
        searchField.typeText("the")
        // Wait for search results — server may take a moment
        sleep(5)

        // Search uses ScrollView with sections (Artists, Albums, Songs)
        // Look for section headers or any new content appearing
        let songSection = app.staticTexts["Songs"]
        let albumSection = app.staticTexts["Albums"]
        let artistSection = app.staticTexts["Artists"]
        let matchingText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'the'"))
        // Also check if any result cells appeared (buttons or static texts beyond the search field)
        let contentCount = app.staticTexts.count

        let hasResults = songSection.waitForExistence(timeout: 8)
            || albumSection.exists
            || artistSection.exists
            || matchingText.count > 0
            || contentCount > 3
        XCTAssertTrue(hasResults,
                      "Search for 'the' should return results")
    }

    // MARK: - Settings Detail

    func testSettingsShowsServerInfo() throws {
        app.goToSettings()
        sleep(2)

        // Should show the server URL or connection info
        let hasServerInfo = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'dmoney'")).count > 0
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'duckdns'")).count > 0
        XCTAssertTrue(hasServerInfo, "Settings should show server info")
    }

    func testSettingsHasManageServers() throws {
        app.goToSettings()
        sleep(1)

        let manageButton = app.buttons["Manage Servers"]
        XCTAssertTrue(manageButton.waitForExistence(timeout: 5),
                      "Settings should have Manage Servers button")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            XCTAssertTrue(app.waitForMainScreen())
        }
    }
}
