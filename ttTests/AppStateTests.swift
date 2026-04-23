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

    @MainActor
    override func tearDown() {
        appState = nil
        dbQueue = nil
        super.tearDown()
    }

    @MainActor
    func testLoadInitialStateSurfacesError() async {
        // Drop tables so loadInitialState fails
        try! dbQueue.write { db in try db.drop(table: "timeEntries") }

        await appState.loadInitialState()

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testStartTimerSurfacesError() async {
        await appState.loadInitialState()
        try! dbQueue.write { db in try db.drop(table: "timeEntries") }

        appState.startTimer()

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testStopTimerSurfacesError() async {
        await appState.loadInitialState()
        appState.startTimer()
        XCTAssertNil(appState.lastError)

        try! dbQueue.write { db in try db.drop(table: "timeEntries") }

        appState.stopTimer()

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testCreateProjectSurfacesError() async {
        await appState.loadInitialState()
        try! dbQueue.write { db in try db.drop(table: "projects") }

        appState.createProject(name: "fail")

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testArchiveProjectSurfacesError() async {
        await appState.loadInitialState()
        let projectId = appState.projects.first!.id
        try! dbQueue.write { db in try db.drop(table: "projects") }

        appState.archiveProject(id: projectId)

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testDeleteEntrySurfacesError() async {
        await appState.loadInitialState()
        appState.startTimer()
        let entryId = appState.runningEntry!.id
        try! dbQueue.write { db in try db.drop(table: "timeEntries") }

        appState.deleteEntry(id: entryId)

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testUpdateEntrySurfacesError() async {
        await appState.loadInitialState()
        appState.startTimer()
        appState.stopTimer()
        let entryId = appState.todaysEntries.first!.id
        try! dbQueue.write { db in try db.drop(table: "timeEntries") }

        appState.updateEntry(id: entryId, start: Date(), end: Date(), note: nil)

        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testDismissErrorClearsLastError() async {
        await appState.loadInitialState()
        try! dbQueue.write { db in try db.drop(table: "timeEntries") }
        appState.startTimer()
        XCTAssertNotNil(appState.lastError)

        appState.dismissError()

        XCTAssertNil(appState.lastError)
    }
}
