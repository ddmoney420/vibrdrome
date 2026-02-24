import XCTest

/// Tests that verify the app launches correctly on macOS.
final class MacLaunchTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    func testAppLaunchesSuccessfully() throws {
        app.launch()
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground,
                      "App should launch and remain in foreground")
    }

    func testAppShowsLoginOrMainScreen() throws {
        app.launch()
        let showsLogin = app.isOnLoginScreen
        let showsMain = app.isOnMainScreen
        XCTAssertTrue(showsLogin || showsMain,
                      "App should show login or main screen after launch")
    }
}
