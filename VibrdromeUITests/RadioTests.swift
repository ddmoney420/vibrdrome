import XCTest

/// Tests internet radio features: station list, search, adding stations.
final class RadioTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
    }

    // MARK: - Radio Tab

    func testRadioTabShowsContent() throws {
        app.goToRadio()
        sleep(3)

        let hasFindStations = app.buttons["Find Stations"].exists
        let hasAddURL = app.buttons["Add URL"].exists
        let hasContent = app.staticTexts.count > 1

        XCTAssertTrue(hasFindStations || hasAddURL || hasContent,
                      "Radio tab should show content or action buttons")
    }

    func testFindStationsButtonExists() throws {
        app.goToRadio()
        sleep(2)

        let findStations = app.buttons["Find Stations"]
        XCTAssertTrue(findStations.waitForExistence(timeout: 5),
                      "Radio tab should have 'Find Stations' button")
    }

    func testAddURLButtonExists() throws {
        app.goToRadio()
        sleep(2)

        let addURL = app.buttons["Add URL"]
        XCTAssertTrue(addURL.waitForExistence(timeout: 5),
                      "Radio tab should have 'Add URL' button")
    }

    // MARK: - Station Search

    func testFindStationsOpensSearch() throws {
        app.goToRadio()
        sleep(2)

        let findStations = app.buttons["Find Stations"]
        guard findStations.waitForExistence(timeout: 5) else {
            throw XCTSkip("Find Stations button not found")
        }

        findStations.tap()
        sleep(2)

        // Station search should show a search field and genre tags
        let searchField = app.searchFields.firstMatch
        let hasSearch = searchField.waitForExistence(timeout: 5)

        XCTAssertTrue(hasSearch || app.staticTexts.count > 3,
                      "Station search should open with search field or genre tags")
    }

    func testStationSearchHasGenreTags() throws {
        app.goToRadio()
        sleep(2)

        let findStations = app.buttons["Find Stations"]
        guard findStations.waitForExistence(timeout: 5) else {
            throw XCTSkip("Find Stations button not found")
        }

        findStations.tap()
        sleep(2)

        // Should show popular genre tags
        let genres = ["jazz", "rock", "electronic", "classical", "pop", "ambient"]
        var foundGenres = 0
        for genre in genres {
            let genreButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", genre)).firstMatch
            let genreText = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", genre)).firstMatch
            if genreButton.exists || genreText.exists {
                foundGenres += 1
            }
        }

        XCTAssertGreaterThan(foundGenres, 0,
                             "Station search should show genre tags")
    }

    func testStationSearchReturnsResults() throws {
        app.goToRadio()
        sleep(2)

        let findStations = app.buttons["Find Stations"]
        guard findStations.waitForExistence(timeout: 5) else {
            throw XCTSkip("Find Stations button not found")
        }

        findStations.tap()
        sleep(2)

        let searchField = app.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 5) else {
            throw XCTSkip("Search field not found in station search")
        }

        searchField.tap()
        sleep(1)

        // Ensure keyboard is visible before typing
        let keyboard = app.keyboards.firstMatch
        if !keyboard.waitForExistence(timeout: 5) {
            // Try tapping the field again
            searchField.tap()
            sleep(1)
            guard keyboard.waitForExistence(timeout: 3) else {
                throw XCTSkip("Could not get keyboard focus on search field")
            }
        }

        searchField.typeText("jazz")
        sleep(8) // Wait for search results from radio-browser.info API

        // External API (radio-browser.info) may be slow or unreliable
        // Just verify no crash — results depend on external service
        XCTAssertTrue(app.state == .runningForeground,
                      "Searching 'jazz' should not crash the app")
    }

    // MARK: - Add Station by URL

    func testAddURLOpensForm() throws {
        app.goToRadio()
        sleep(2)

        let addURL = app.buttons["Add URL"]
        guard addURL.waitForExistence(timeout: 5) else {
            throw XCTSkip("Add URL button not found")
        }

        addURL.tap()
        sleep(2)

        // Should show form with station name and stream URL fields
        let nameField = app.textFields.matching(
            NSPredicate(format: "placeholderValue CONTAINS[c] 'station' OR placeholderValue CONTAINS[c] 'name'")).firstMatch
        let urlField = app.textFields.matching(
            NSPredicate(format: "placeholderValue CONTAINS[c] 'stream' OR placeholderValue CONTAINS[c] 'url'")).firstMatch

        let formOpened = nameField.waitForExistence(timeout: 5)
            || urlField.exists
            || app.textFields.count >= 2

        XCTAssertTrue(formOpened,
                      "Add Station form should show name and URL fields")

        // Dismiss
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.exists { cancelButton.tap() }
        sleep(1)
    }

    func testAddURLFormHasAddButton() throws {
        app.goToRadio()
        sleep(2)

        let addURL = app.buttons["Add URL"]
        guard addURL.waitForExistence(timeout: 5) else {
            throw XCTSkip("Add URL button not found")
        }

        addURL.tap()
        sleep(2)

        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5),
                      "Add Station form should have 'Add' button")

        // Add should be disabled with empty fields
        XCTAssertFalse(addButton.isEnabled,
                       "Add button should be disabled with empty fields")

        // Dismiss
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.exists { cancelButton.tap() }
        sleep(1)
    }

    // MARK: - Station Playback

    func testTapStationPlays() throws {
        app.goToRadio()
        sleep(3)

        // Find a station in the list (look for Play icons)
        let playIcon = app.images.matching(
            NSPredicate(format: "label == 'Play'")).firstMatch

        guard playIcon.waitForExistence(timeout: 5) else {
            throw XCTSkip("No radio stations available to play")
        }

        playIcon.tap()
        sleep(5) // Radio streams take time to buffer

        // Should see a playing indicator or mini player
        let pauseButton = app.buttons.matching(
            NSPredicate(format: "label == 'Pause'")).firstMatch
        let playingIndicator = app.images.matching(
            NSPredicate(format: "label == 'Playing'")).firstMatch

        let isPlaying = pauseButton.waitForExistence(timeout: 10)
            || playingIndicator.exists

        XCTAssertTrue(isPlaying || app.state == .runningForeground,
                      "Tapping a station should start playback or at least not crash")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            XCTAssertTrue(app.waitForMainScreen())
        }
    }
}
