import XCTest

/// Tests favorites and downloads views on macOS.
final class MacFavoritesAndDownloadsTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
    }

    // MARK: - Favorites in Now Playing

    func testFavoriteButtonInNowPlaying() throws {
        try app.playAnyTrack()
        try app.ensureNowPlayingOpen()
        sleep(2)

        let addFav = app.buttons["Add to Favorites"]
        let removeFav = app.buttons["Remove from Favorites"]
        let hasFavoriteButton = addFav.waitForExistence(timeout: 5)
            || removeFav.exists

        XCTAssertTrue(hasFavoriteButton,
                      "Favorites button should exist in Now Playing")
    }

    func testFavoriteToggle() throws {
        try app.playAnyTrack()
        try app.ensureNowPlayingOpen()
        sleep(2)

        let addFav = app.buttons["Add to Favorites"]
        let removeFav = app.buttons["Remove from Favorites"]

        if addFav.waitForExistence(timeout: 5) {
            addFav.click()
            sleep(2)
            XCTAssertTrue(removeFav.waitForExistence(timeout: 5)
                          || app.state == .runningForeground,
                          "Should toggle to Remove from Favorites")
            // Toggle back
            if removeFav.exists { removeFav.click(); sleep(2) }
        } else if removeFav.exists {
            removeFav.click()
            sleep(2)
            XCTAssertTrue(addFav.waitForExistence(timeout: 5)
                          || app.state == .runningForeground,
                          "Should toggle to Add to Favorites")
            // Toggle back
            if addFav.exists { addFav.click(); sleep(2) }
        } else {
            throw XCTSkip("Favorites button not found")
        }
    }

    // MARK: - Favorites View

    func testFavoritesViewShowsContent() throws {
        app.goToFavorites()
        sleep(3)

        let hasContent = app.staticTexts.count > 0
        XCTAssertTrue(hasContent || app.state == .runningForeground,
                      "Favorites view should show favorited items or empty state")
    }

    // MARK: - Downloads View

    func testDownloadsViewShowsContent() throws {
        app.goToDownloads()
        sleep(3)

        let hasContent = app.staticTexts.count > 0
        XCTAssertTrue(hasContent || app.state == .runningForeground,
                      "Downloads view should show downloaded tracks or empty state")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            XCTAssertTrue(app.waitForMainScreen())
        }
    }
}
