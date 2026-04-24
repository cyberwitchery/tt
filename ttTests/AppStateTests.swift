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

final class AppStateErrorTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var appState: AppState!

    @MainActor
    override func setUp() async throws {
        dbQueue = try TestDatabase.makeInMemory()
        let projectRepo = ProjectRepository(dbQueue: dbQueue)
        let entryRepo = TimeEntryRepository(dbQueue: dbQueue)
        let tracker = TimeTracker(
            projectRepository: projectRepo,
            timeEntryRepository: entryRepo
        )
        appState = AppState(tracker: tracker)
    }

    @MainActor
    override func tearDown() async throws {
        appState?.dismissError()
        appState = nil
        dbQueue = nil
    }

    /// Uses the synchronous GRDB write overload so the table drop runs on
    /// the same serial queue path as the repository operations that follow.
    /// The previous `await dbQueue.write` resolved to the async overload,
    /// which interacted poorly with @MainActor parallel test execution.
    @MainActor
    private func dropTable(_ name: String) {
        try! dbQueue.write { db in
            try db.drop(table: name)
        }
    }

    @MainActor
    func testLoadInitialStateSurfacesError() async {
        dropTable("timeEntries")

        await appState.loadInitialState()

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testStartTimerSurfacesError() async {
        await appState.loadInitialState()
        dropTable("timeEntries")

        appState.startTimer()

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testStopTimerSurfacesError() async {
        await appState.loadInitialState()
        appState.startTimer()
        XCTAssertNil(appState.lastError)

        dropTable("timeEntries")

        appState.stopTimer()

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testCreateProjectSurfacesError() async {
        await appState.loadInitialState()
        dropTable("projects")

        appState.createProject(name: "fail")

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testArchiveProjectSurfacesError() async throws {
        await appState.loadInitialState()
        let projectId = try XCTUnwrap(appState.projects.first?.id)
        dropTable("projects")

        appState.archiveProject(id: projectId)

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testDeleteEntrySurfacesError() async throws {
        await appState.loadInitialState()
        appState.startTimer()
        let entryId = try XCTUnwrap(appState.runningEntry?.id)
        dropTable("timeEntries")

        appState.deleteEntry(id: entryId)

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testUpdateEntrySurfacesError() async throws {
        await appState.loadInitialState()
        appState.startTimer()
        appState.stopTimer()
        let entryId = try XCTUnwrap(appState.todaysEntries.first?.id)
        dropTable("timeEntries")

        appState.updateEntry(id: entryId, start: Date(), end: Date(), note: nil)

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testDismissErrorClearsLastError() async {
        await appState.loadInitialState()
        dropTable("timeEntries")
        appState.startTimer()
        XCTAssertNotNil(appState.lastError)

        appState.dismissError()

        XCTAssertNil(appState.lastError)
    }
}
