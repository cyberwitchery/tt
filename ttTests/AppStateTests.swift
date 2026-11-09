import XCTest
import Combine
import GRDB
@testable import tt

final class AppStateTests: XCTestCase {
    @MainActor
    func testBootstrapLoadsAnIsolatedMigratedDatabase() throws {
        let state = AppState(database: .success(try DatabaseManager()))
        XCTAssertEqual(state.projects.map(\.name), ["default"])
        XCTAssertNil(state.lastError)
        state.startTimer()
        XCTAssertNotNil(state.runningEntry)
        state.stopTimer()
        XCTAssertNil(state.runningEntry)
    }

    @MainActor
    func testBootstrapSurfacesTheDatabaseOpenFailure() throws {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "database unavailable"])
        let state = AppState(database: .failure(error))
        XCTAssertNotNil(state.lastError)
        XCTAssertTrue(state.projects.isEmpty)
    }

    @MainActor
    func testSelectProjectUpdatesState() throws {
        let db = try TestDatabase.makeInMemory()
        let tracker = TimeTracker(projectRepository: ProjectRepository(dbQueue: db), timeEntryRepository: TimeEntryRepository(dbQueue: db))
        let appState = AppState(tracker: tracker)
        appState.selectProject(id: "test-id")
        XCTAssertEqual(appState.selectedProjectId, "test-id")
        XCTAssertEqual(appState.projectName(for: "missing"), "unknown")
    }
}

// MARK: - Error Propagation

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

    @MainActor
    func testEntryReadFailureShowsAnErrorAndRetainsTheLastEntries() {
        let state = makeAppState()
        state.loadInitialState()
        state.startTimer()
        let entries = state.visibleEntries
        dropTable("time_entries")
        state.refreshEntries()
        XCTAssertNotNil(state.lastError)
        XCTAssertEqual(state.visibleEntries, entries)
        state.stepDay(by: -1)
        XCTAssertTrue(state.isViewingToday)
        XCTAssertEqual(state.visibleEntries, entries)
    }

    @MainActor
    func testProjectReadFailureRetainsAValidSelection() {
        let state = makeAppState()
        state.loadInitialState()
        let projects = state.projects
        let selection = state.selectedProjectId
        dropTable("projects")
        state.refreshProjects()
        XCTAssertNotNil(state.lastError)
        XCTAssertEqual(state.projects, projects)
        XCTAssertEqual(state.selectedProjectId, selection)
        XCTAssertTrue(state.projects.contains { $0.id == selection })
    }

    @MainActor
    func testReportReadFailureRetainsTheLastTotals() {
        let state = makeAppState()
        state.loadInitialState()
        state.startTimer()
        state.stopTimer()
        state.refreshReports()
        let totals = state.projectTotalsForSelectedDay
        dropTable("time_entries")
        state.refreshReports()
        XCTAssertNotNil(state.lastError)
        XCTAssertEqual(state.projectTotalsForSelectedDay, totals)
    }

    func testLoadInitialStateSurfacesError() async {
        let appState = await makeAppState()
        dropTable("time_entries")
        await appState.loadInitialState()
        let error = await appState.lastError
        XCTAssertNotNil(error)
    }

    func testStartTimerSurfacesError() async {
        let appState = await makeAppState()
        await appState.loadInitialState()
        dropTable("time_entries")
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

        dropTable("time_entries")
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
        dropTable("time_entries")
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
        dropTable("time_entries")
        await appState.updateEntry(id: entryId, start: Date(), end: Date(), note: nil)
        let error = await appState.lastError
        XCTAssertNotNil(error)
    }

    func testDismissErrorClearsLastError() async {
        let appState = await makeAppState()
        await appState.loadInitialState()
        dropTable("time_entries")
        await appState.startTimer()
        let error = await appState.lastError
        XCTAssertNotNil(error)

        await appState.dismissError()
        let cleared = await appState.lastError
        XCTAssertNil(cleared)
    }
}

// MARK: - Day Browsing

final class AppStateDayBrowsingTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var entryRepository: TimeEntryRepository!
    private var clock = TestClock()

    override func setUp() {
        super.setUp()
        clock = TestClock()
        dbQueue = try! TestDatabase.makeInMemory()
        entryRepository = TimeEntryRepository(dbQueue: dbQueue)
    }

    override func tearDown() {
        dbQueue = nil
        entryRepository = nil
        super.tearDown()
    }

    private func makeTracker() -> TimeTracker {
        TimeTracker(
            projectRepository: ProjectRepository(dbQueue: dbQueue),
            timeEntryRepository: entryRepository,
            days: clock.days
        )
    }

    @MainActor
    private func makeAppState() -> AppState {
        AppState(tracker: makeTracker())
    }

    private func time(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @MainActor
    func testTrackerChangesAreObservedWithoutCopyingState() throws {
        clock.now = Date.from(year: 2026, month: 1, day: 1, hour: 9)
        let tracker = makeTracker()
        let appState = AppState(tracker: tracker)
        var notifications = 0
        let observation = appState.objectWillChange.sink { notifications += 1 }
        defer { observation.cancel() }
        try tracker.loadInitialState()
        try tracker.createProject(name: "new")
        XCTAssertEqual(appState.projects, tracker.projects)
        XCTAssertGreaterThan(notifications, 0)
        try tracker.startTimer()
        let projectId = try XCTUnwrap(tracker.runningEntry?.projectId)
        clock.now = clock.now.addingTimeInterval(125)
        XCTAssertEqual(appState.elapsedSeconds, 125)
        XCTAssertEqual(appState.projectAllTimeSeconds(for: projectId), tracker.projectAllTimeSeconds(for: projectId))
        XCTAssertEqual(appState.todayTotalSeconds(), 125)
        try tracker.stopTimer()
        XCTAssertNil(appState.runningEntry)
        XCTAssertEqual(appState.projectAllTimeSeconds(for: projectId), 125)
    }

    @MainActor
    func testStepDayExposesThePreviousDaysEntries() async throws {
        let appState = makeAppState()
        appState.loadInitialState()
        let projectId = appState.projects[0].id
        let yesterday = TimeEntry(projectId: projectId, start: time(daysAgo: 1, hour: 9), end: time(daysAgo: 1, hour: 10))
        let today = TimeEntry(projectId: projectId, start: time(daysAgo: 0, hour: 9), end: time(daysAgo: 0, hour: 10))
        try entryRepository.insertRunning(entry: yesterday)
        try entryRepository.insertRunning(entry: today)
        appState.refreshEntries()

        appState.stepDay(by: -1)

        XCTAssertFalse(appState.isViewingToday)
        XCTAssertEqual(appState.selectedDay, Calendar.current.startOfDay(for: time(daysAgo: 1, hour: 9)))
        XCTAssertEqual(appState.visibleEntries.map(\.id), [yesterday.id])
        XCTAssertEqual(appState.todaysEntries.map(\.id), [today.id])
    }

    @MainActor
    func testShowTodayReturnsToTheCurrentDay() async throws {
        let appState = makeAppState()
        appState.loadInitialState()
        appState.stepDay(by: -3)

        appState.showToday()

        XCTAssertTrue(appState.isViewingToday)
        XCTAssertEqual(appState.selectedDay, Calendar.current.startOfDay(for: Date()))
    }

    @MainActor
    func testTheTwoDayTotalsSplitAnEntrySpanningMidnight() async throws {
        let appState = makeAppState()
        appState.loadInitialState()
        let start = time(daysAgo: 1, hour: 23)
        let end = time(daysAgo: 0, hour: 1)
        try entryRepository.insertRunning(
            entry: TimeEntry(projectId: appState.projects[0].id, start: start, end: end)
        )
        appState.refreshEntries()

        let midnight = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(appState.todayTotalSeconds(), Int(end.timeIntervalSince(midnight)))
        XCTAssertEqual(appState.visibleDayTotalSeconds(), Int(end.timeIntervalSince(midnight)))

        appState.stepDay(by: -1)

        XCTAssertEqual(appState.todayTotalSeconds(), Int(end.timeIntervalSince(midnight)))
        XCTAssertEqual(appState.visibleDayTotalSeconds(), Int(midnight.timeIntervalSince(start)))
    }

    @MainActor
    func testTickRollsTheEntryListOntoTheNewDay() async throws {
        let tracker = makeTracker()
        let appState = AppState(tracker: tracker)
        appState.loadInitialState()
        let projectId = appState.projects[0].id
        let today = TimeEntry(
            projectId: projectId,
            start: time(daysAgo: 0, hour: 9),
            end: time(daysAgo: 0, hour: 10)
        )
        try entryRepository.insertRunning(
            entry: TimeEntry(
                projectId: projectId,
                start: time(daysAgo: 1, hour: 9),
                end: time(daysAgo: 1, hour: 10)
            )
        )
        try entryRepository.insertRunning(entry: today)
        clock.now = time(daysAgo: 1, hour: 23)
        try tracker.refreshEntries()
        XCTAssertEqual(appState.visibleEntries.count, 1)

        clock.now = time(daysAgo: 0, hour: 0, minute: 30)
        appState.tick()

        XCTAssertEqual(appState.visibleEntries.map(\.id), [today.id])
        XCTAssertEqual(appState.selectedDay, Calendar.current.startOfDay(for: Date()))
    }
}
