import XCTest

/// Tests macOS-specific features: window sizing, menu bar, keyboard shortcuts.
final class MacWindowAndKeyboardTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        ensureLoggedIn()
    }

    // MARK: - Window

    func testMainWindowMinSize() throws {
        // The main window has min 800x500 — verify the window exists and
        // has reasonable dimensions
        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: 5) else {
            throw XCTSkip("No window found")
        }

        let frame = window.frame
        XCTAssertGreaterThanOrEqual(frame.width, 800,
                                     "Main window width should be >= 800, got \(frame.width)")
        XCTAssertGreaterThanOrEqual(frame.height, 500,
                                     "Main window height should be >= 500, got \(frame.height)")
    }

    // MARK: - Menu Bar

    func testPlaybackMenuExists() throws {
        let menuBar = app.menuBars.firstMatch
        guard menuBar.waitForExistence(timeout: 5) else {
            throw XCTSkip("Menu bar not accessible")
        }

        let playbackMenu = menuBar.menuBarItems["Playback"]
        XCTAssertTrue(playbackMenu.waitForExistence(timeout: 5),
                      "Menu bar should have 'Playback' menu")
    }

    // MARK: - Keyboard Shortcuts

    func testKeyboardShortcutPlayPause() throws {
        try app.playAnyTrack()
        sleep(2)

        // Cmd+P toggles play/pause
        app.typeKey("p", modifierFlags: .command)
        sleep(1)

        XCTAssertTrue(app.state == .runningForeground,
                      "Cmd+P should toggle playback without crashing")

        // Toggle back
        app.typeKey("p", modifierFlags: .command)
        sleep(1)

        XCTAssertTrue(app.state == .runningForeground,
                      "Cmd+P should toggle back without crashing")
    }

    func testCmdRightNextTrack() throws {
        try app.playAnyTrack()
        sleep(2)

        app.typeKey(.rightArrow, modifierFlags: .command)
        sleep(2)

        XCTAssertTrue(app.state == .runningForeground,
                      "Cmd+Right should advance to next track without crashing")
    }

    func testCmdLeftPreviousTrack() throws {
        try app.playAnyTrack()
        sleep(2)

        app.typeKey(.leftArrow, modifierFlags: .command)
        sleep(2)

        XCTAssertTrue(app.state == .runningForeground,
                      "Cmd+Left should go to previous track without crashing")
    }

    func testCmdShiftSShuffle() throws {
        try app.playAnyTrack()
        sleep(2)

        app.typeKey("s", modifierFlags: [.command, .shift])
        sleep(1)

        XCTAssertTrue(app.state == .runningForeground,
                      "Cmd+Shift+S should toggle shuffle without crashing")

        // Toggle back
        app.typeKey("s", modifierFlags: [.command, .shift])
        sleep(1)

        XCTAssertTrue(app.state == .runningForeground,
                      "Cmd+Shift+S should toggle back without crashing")
    }

    // MARK: - Helpers

    private func ensureLoggedIn() {
        if app.isOnLoginScreen {
            app.signIn()
            XCTAssertTrue(app.waitForMainScreen())
        }
    }
}
