import XCTest
import GRDB
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

// MARK: - Error Propagation

/// Tests run without @MainActor on the class to avoid crashes in Xcode's
/// parallel test worker processes (each spawned PID dies at 0.000s when the
/// class is @MainActor). Instead, each test is async and crosses the actor
/// boundary with `await` — matching the pattern AppStateTests already uses.
final class AppStateErrorTests: XCTestCase {
    private var dbQueue: DatabaseQueue!

    override func setUp() {
        super.setUp()
        dbQueue = try! TestDatabase.makeInMemory()
    }

    override func tearDown() {
        dbQueue = nil
        super.tearDown()
    }

    private func dropTable(_ name: String) {
        try! dbQueue.write { db in
            try db.drop(table: name)
        }
    }

    @MainActor
    private func makeAppState() -> AppState {
        let projectRepo = ProjectRepository(dbQueue: dbQueue)
        let entryRepo = TimeEntryRepository(dbQueue: dbQueue)
        let tracker = TimeTracker(
            projectRepository: projectRepo,
            timeEntryRepository: entryRepo
        )
        return AppState(tracker: tracker)
    }

    func testLoadInitialStateSurfacesError() async {
        let appState = await makeAppState()
        dropTable("timeEntries")
        await appState.loadInitialState()
        let error = await appState.lastError
        XCTAssertNotNil(error)
    }

    func testStartTimerSurfacesError() async {
        let appState = await makeAppState()
        await appState.loadInitialState()
        dropTable("timeEntries")
        await appState.startTimer()
        let error = await appState.lastError
        XCTAssertNotNil(error)
    }

    func testStopTimerSurfacesError() async {
        let appState = await makeAppState()
        await appState.loadInitialState()
        await appState.startTimer()
        let preError = await appState.lastError
        XCTAssertNil(preError)

        dropTable("timeEntries")
        await appState.stopTimer()
        let error = await appState.lastError
        XCTAssertNotNil(error)
    }

    func testCreateProjectSurfacesError() async {
        let appState = await makeAppState()
        await appState.loadInitialState()
        dropTable("projects")
        await appState.createProject(name: "fail")
        let error = await appState.lastError
        XCTAssertNotNil(error)
    }

    func testArchiveProjectSurfacesError() async throws {
        let appState = await makeAppState()
        await appState.loadInitialState()
        let projects = await appState.projects
        let projectId = try XCTUnwrap(projects.first?.id)
        dropTable("projects")
        await appState.archiveProject(id: projectId)
        let error = await appState.lastError
        XCTAssertNotNil(error)
    }

    func testDeleteEntrySurfacesError() async throws {
        let appState = await makeAppState()
        await appState.loadInitialState()
        await appState.startTimer()
        let running = await appState.runningEntry
        let entryId = try XCTUnwrap(running?.id)
        dropTable("timeEntries")
        await appState.deleteEntry(id: entryId)
        let error = await appState.lastError
        XCTAssertNotNil(error)
    }

    func testUpdateEntrySurfacesError() async throws {
        let appState = await makeAppState()
        await appState.loadInitialState()
        await appState.startTimer()
        await appState.stopTimer()
        let entries = await appState.todaysEntries
        let entryId = try XCTUnwrap(entries.first?.id)
        dropTable("timeEntries")
        await appState.updateEntry(id: entryId, start: Date(), end: Date(), note: nil)
        let error = await appState.lastError
        XCTAssertNotNil(error)
    }

    func testDismissErrorClearsLastError() async {
        let appState = await makeAppState()
        await appState.loadInitialState()
        dropTable("timeEntries")
        await appState.startTimer()
        let error = await appState.lastError
        XCTAssertNotNil(error)

        await appState.dismissError()
        let cleared = await appState.lastError
        XCTAssertNil(cleared)
    }
}
