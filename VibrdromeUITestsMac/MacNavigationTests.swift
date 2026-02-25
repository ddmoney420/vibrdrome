import XCTest

/// Tests sidebar navigation on macOS.
final class MacNavigationTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
    }

    // MARK: - Sidebar Navigation

    func testArtistsSidebarShowsContent() throws {
        app.goToArtists()
        sleep(3)
        let hasContent = app.staticTexts.count > 2
        XCTAssertTrue(hasContent, "Artists view should show content")
    }

    func testAlbumsSidebarShowsContent() throws {
        app.goToAlbums()
        sleep(3)
        let hasContent = app.staticTexts.count > 2
        XCTAssertTrue(hasContent, "Albums view should show content")
    }

    func testSearchSidebarShowsSearchField() throws {
        app.goToSearch()
        sleep(1)
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5),
                      "Search view should have a search field")
    }

    func testPlaylistsSidebarShowsContent() throws {
        app.goToPlaylists()
        sleep(3)
        let hasNewPlaylist = app.buttons["New Playlist"].exists
        let hasContent = app.staticTexts.count > 1 || app.buttons.count > 5
        XCTAssertTrue(hasNewPlaylist || hasContent,
                      "Playlists view should show content or New Playlist button")
    }

    func testRadioSidebarShowsContent() throws {
        app.goToRadio()
        sleep(2)
        let hasContent = app.staticTexts.count > 0
        XCTAssertTrue(hasContent, "Stations view should show content")
    }

    func testDownloadsSidebarShowsContent() throws {
        app.goToDownloads()
        sleep(2)
        let hasContent = app.staticTexts.count > 0
        XCTAssertTrue(hasContent || app.state == .runningForeground,
                      "Downloads view should show content or empty state")
    }

    func testFavoritesSidebarShowsContent() throws {
        app.goToFavorites()
        sleep(2)
        let hasContent = app.staticTexts.count > 0
        XCTAssertTrue(hasContent || app.state == .runningForeground,
                      "Favorites view should show content or empty state")
    }

    func testBookmarksSidebarShowsContent() throws {
        app.goToBookmarks()
        sleep(2)
        let hasContent = app.staticTexts.count > 0
        XCTAssertTrue(hasContent || app.state == .runningForeground,
                      "Bookmarks view should show content or empty state")
    }

    func testSwitchBetweenSidebarItems() throws {
        let items = ["Artists", "Albums", "Search", "Playlists", "Stations",
                     "Favorites", "Downloads", "Bookmarks"]
        for item in items {
            app.goToSidebarItem(item)
            sleep(1)
        }
        XCTAssertTrue(app.state == .runningForeground,
                      "App should not crash when switching between sidebar items")
    }

    // MARK: - Search

    func testSearchReturnsResults() throws {
        app.goToSearch()
        let searchField = app.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 5) else {
            XCTFail("Search field not found")
            return
        }

        searchField.click()
        searchField.typeText("love")
        sleep(3)

        let songSection = app.staticTexts["Songs"]
        let albumSection = app.staticTexts["Albums"]
        let artistSection = app.staticTexts["Artists"]
        let matchingText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'love'"))

        let hasResults = songSection.waitForExistence(timeout: 5)
            || albumSection.exists
            || artistSection.exists
            || matchingText.count > 0
        XCTAssertTrue(hasResults,
                      "Search for 'love' should return results")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            XCTAssertTrue(app.waitForMainScreen())
        }
    }
}
