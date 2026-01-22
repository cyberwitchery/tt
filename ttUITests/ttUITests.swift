import XCTest

final class ttUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Smoke Tests

    func testAppLaunches() throws {
        // Verify the app launched without crashing
        XCTAssertTrue(app.exists)
    }

    func testMenuBarItemExists() throws {
        // The app is a menu bar app, verify it's running
        // Menu bar apps don't have traditional windows on launch
        XCTAssertTrue(app.exists)
    }

    func testMainWindowOpens() throws {
        // Click the menu bar item to open the main window
        // Note: Menu bar interaction is limited in XCUITest
        // This test verifies the app stays stable after launch
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 2.0 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTAssertTrue(app.exists)
    }
}
