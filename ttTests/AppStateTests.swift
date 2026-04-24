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

/// Tests are @MainActor at the class level with synchronous setUp/tearDown.
/// Previous iterations used `@MainActor override func setUp() async throws`
/// which crashes Xcode's parallel test workers (each worker process dies at
/// 0.000s before the test body runs). The fix: synchronous lifecycle methods
/// plus synchronous test methods — `loadInitialState()` was async-in-name-only
/// (no awaits inside), so removing the `async` keyword lets us drop the async
/// test execution path entirely.
@MainActor
final class AppStateErrorTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var appState: AppState!

    override func setUp() {
        super.setUp()
        dbQueue = try! TestDatabase.makeInMemory()
        let projectRepo = ProjectRepository(dbQueue: dbQueue)
        let entryRepo = TimeEntryRepository(dbQueue: dbQueue)
        let tracker = TimeTracker(
            projectRepository: projectRepo,
            timeEntryRepository: entryRepo
        )
        appState = AppState(tracker: tracker)
    }

    override func tearDown() {
        appState?.dismissError()
        appState = nil
        dbQueue = nil
        super.tearDown()
    }

    private func dropTable(_ name: String) {
        try! dbQueue.write { db in
            try db.drop(table: name)
        }
    }

    func testLoadInitialStateSurfacesError() {
        dropTable("timeEntries")

        appState.loadInitialState()

        XCTAssertNotNil(appState.lastError)
    }

    func testStartTimerSurfacesError() {
        appState.loadInitialState()
        dropTable("timeEntries")

        appState.startTimer()

        XCTAssertNotNil(appState.lastError)
    }

    func testStopTimerSurfacesError() {
        appState.loadInitialState()
        appState.startTimer()
        XCTAssertNil(appState.lastError)

        dropTable("timeEntries")

        appState.stopTimer()

        XCTAssertNotNil(appState.lastError)
    }

    func testCreateProjectSurfacesError() {
        appState.loadInitialState()
        dropTable("projects")

        appState.createProject(name: "fail")

        XCTAssertNotNil(appState.lastError)
    }

    func testArchiveProjectSurfacesError() throws {
        appState.loadInitialState()
        let projectId = try XCTUnwrap(appState.projects.first?.id)
        dropTable("projects")

        appState.archiveProject(id: projectId)

        XCTAssertNotNil(appState.lastError)
    }

    func testDeleteEntrySurfacesError() throws {
        appState.loadInitialState()
        appState.startTimer()
        let entryId = try XCTUnwrap(appState.runningEntry?.id)
        dropTable("timeEntries")

        appState.deleteEntry(id: entryId)

        XCTAssertNotNil(appState.lastError)
    }

    func testUpdateEntrySurfacesError() throws {
        appState.loadInitialState()
        appState.startTimer()
        appState.stopTimer()
        let entryId = try XCTUnwrap(appState.todaysEntries.first?.id)
        dropTable("timeEntries")

        appState.updateEntry(id: entryId, start: Date(), end: Date(), note: nil)

        XCTAssertNotNil(appState.lastError)
    }

    func testDismissErrorClearsLastError() {
        appState.loadInitialState()
        dropTable("timeEntries")
        appState.startTimer()
        XCTAssertNotNil(appState.lastError)

        appState.dismissError()

        XCTAssertNil(appState.lastError)
    }
}
