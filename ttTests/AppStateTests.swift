import XCTest
@testable import tt

// AppState is now a thin UI wrapper around TimeTracker.
// Core business logic is tested in TimeTrackerTests.
// These tests verify the wrapper properly delegates to TimeTracker.

final class AppStateTests: XCTestCase {
    func testSelectProjectUpdatesState() async {
        let appState = await AppState.shared
        await appState.selectProject(id: "test-id")
        let selected = await appState.selectedProjectId
        XCTAssertEqual(selected, "test-id")
    }

    func testProjectNameDelegatesToTracker() async {
        let appState = await AppState.shared
        let name = await appState.projectName(for: "nonexistent-id")
        XCTAssertEqual(name, "unknown")
    }
}
