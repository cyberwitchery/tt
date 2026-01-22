import XCTest
@testable import tt

final class AppStateTests: XCTestCase {
    // MARK: - ProjectName Lookup

    func testProjectNameReturnsUnknownForMissingProject() async {
        let appState = await AppState.shared
        let name = await appState.projectName(for: "nonexistent-id")
        XCTAssertEqual(name, "unknown")
    }

    // MARK: - Selection

    func testSelectProject() async {
        let appState = await AppState.shared
        await appState.selectProject(id: "test-id")
        let selected = await appState.selectedProjectId
        XCTAssertEqual(selected, "test-id")
    }

    // MARK: - Create Project with Empty Name

    func testCreateProjectIgnoresEmptyName() async {
        let appState = await AppState.shared
        let initialCount = await appState.projects.count
        await appState.createProject(name: "   ")
        let finalCount = await appState.projects.count
        XCTAssertEqual(initialCount, finalCount)
    }

    func testCreateProjectIgnoresWhitespaceOnlyName() async {
        let appState = await AppState.shared
        let initialCount = await appState.projects.count
        await appState.createProject(name: "\t\n  ")
        let finalCount = await appState.projects.count
        XCTAssertEqual(initialCount, finalCount)
    }
}
