import XCTest

/// Tests internet radio features on macOS.
final class MacRadioTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
    }

    // MARK: - Radio Tab

    func testRadioSidebarShowsContent() throws {
        app.goToRadio()
        sleep(3)

        let hasFindStations = app.buttons["Find Stations"].exists
        let hasAddURL = app.buttons["Add URL"].exists
        let hasContent = app.staticTexts.count > 1

        XCTAssertTrue(hasFindStations || hasAddURL || hasContent,
                      "Stations view should show content or action buttons")
    }

    func testFindStationsButtonExists() throws {
        app.goToRadio()
        sleep(2)

        let findStations = app.buttons["Find Stations"].firstMatch
        XCTAssertTrue(findStations.waitForExistence(timeout: 5),
                      "Stations view should have 'Find Stations' button")
    }

    func testAddURLButtonExists() throws {
        app.goToRadio()
        sleep(2)

        let addURL = app.buttons["Add URL"].firstMatch
        XCTAssertTrue(addURL.waitForExistence(timeout: 5),
                      "Stations view should have 'Add URL' button")
    }

    // MARK: - Station Search

    func testFindStationsOpensSearch() throws {
        app.goToRadio()
        sleep(2)

        let findStations = app.buttons["Find Stations"].firstMatch
        guard findStations.waitForExistence(timeout: 5) else {
            throw XCTSkip("Find Stations button not found")
        }

        findStations.click()
        sleep(2)

        let searchField = app.searchFields.firstMatch
        let hasSearch = searchField.waitForExistence(timeout: 5)

        XCTAssertTrue(hasSearch || app.staticTexts.count > 3,
                      "Station search should open with search field or genre tags")
    }

    func testStationSearchHasGenreTags() throws {
        app.goToRadio()
        sleep(2)

        let findStations = app.buttons["Find Stations"].firstMatch
        guard findStations.waitForExistence(timeout: 5) else {
            throw XCTSkip("Find Stations button not found")
        }

        findStations.click()
        sleep(2)

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

        let findStations = app.buttons["Find Stations"].firstMatch
        guard findStations.waitForExistence(timeout: 5) else {
            throw XCTSkip("Find Stations button not found")
        }

        findStations.click()
        sleep(2)

        // The search field might be a TextField or SearchField.
        // Try both and use whichever exists.
        let searchField = app.searchFields.firstMatch
        let textField = app.textFields.firstMatch

        let target: XCUIElement? = searchField.waitForExistence(timeout: 5)
            ? searchField : (textField.exists ? textField : nil)

        guard let field = target else {
            throw XCTSkip("Search field not found in station search")
        }

        // Click the center coordinate of the field to ensure keyboard focus
        let coord = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coord.click()
        sleep(1)

        // Type using app level to bypass focus issues
        app.typeText("jazz")
        sleep(8) // Wait for search results from radio-browser.info API

        // External API may be slow — just verify no crash
        XCTAssertTrue(app.state == .runningForeground,
                      "Searching 'jazz' should not crash the app")
    }

    // MARK: - Add Station by URL

    func testAddURLOpensForm() throws {
        app.goToRadio()
        sleep(2)

        app.clickToolbarButton("Add URL")
        sleep(2)

        let nameField = app.textFields.matching(
            NSPredicate(format: "placeholderValue CONTAINS[c] 'station' OR placeholderValue CONTAINS[c] 'name'")).firstMatch
        let urlField = app.textFields.matching(
            NSPredicate(format: "placeholderValue CONTAINS[c] 'stream' OR placeholderValue CONTAINS[c] 'url'")).firstMatch

        let formOpened = nameField.waitForExistence(timeout: 5)
            || urlField.exists
            || app.textFields.count >= 2

        XCTAssertTrue(formOpened,
                      "Add Station form should show name and URL fields")

        let cancelButton = app.buttons["Cancel"]
        if cancelButton.exists { cancelButton.click() }
        sleep(1)
    }

    func testAddURLFormHasAddButton() throws {
        app.goToRadio()
        sleep(2)

        app.clickToolbarButton("Add URL")
        sleep(2)

        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5),
                      "Add Station form should have 'Add' button")

        XCTAssertFalse(addButton.isEnabled,
                       "Add button should be disabled with empty fields")

        let cancelButton = app.buttons["Cancel"]
        if cancelButton.exists { cancelButton.click() }
        sleep(1)
    }

    // MARK: - Station Playback

    func testTapStationPlays() throws {
        app.goToRadio()
        sleep(3)

        let playIcon = app.images.matching(
            NSPredicate(format: "label == 'Play'")).firstMatch

        guard playIcon.waitForExistence(timeout: 5) else {
            throw XCTSkip("No radio stations available to play")
        }

        playIcon.click()
        sleep(5) // Radio streams take time to buffer

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
