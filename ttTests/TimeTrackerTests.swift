import XCTest
import GRDB
@testable import tt

final class TimeTrackerTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    var projectRepository: ProjectRepository!
    var timeEntryRepository: TimeEntryRepository!
    var tracker: TimeTracker!

    override func setUp() {
        super.setUp()
        dbQueue = try! TestDatabase.makeInMemory()
        projectRepository = ProjectRepository(dbQueue: dbQueue)
        timeEntryRepository = TimeEntryRepository(dbQueue: dbQueue)
        tracker = TimeTracker(
            projectRepository: projectRepository,
            timeEntryRepository: timeEntryRepository
        )
    }

    override func tearDown() {
        dbQueue = nil
        projectRepository = nil
        timeEntryRepository = nil
        tracker = nil
        super.tearDown()
    }

    // MARK: - Initial Load

    func testLoadInitialStateCreatesDefaultProject() throws {
        try tracker.loadInitialState()

        XCTAssertEqual(tracker.projects.count, 1)
        XCTAssertEqual(tracker.projects[0].name, "default")
        XCTAssertEqual(tracker.selectedProjectId, tracker.projects[0].id)
    }

    func testLoadInitialStateWithExistingProject() throws {
        let project = Project(name: "existing")
        try projectRepository.insert(project)

        try tracker.loadInitialState()

        XCTAssertEqual(tracker.projects.count, 1)
        XCTAssertEqual(tracker.projects[0].name, "existing")
        XCTAssertEqual(tracker.selectedProjectId, project.id)
    }

    func testLoadInitialStateResolvesMultipleRunning() throws {
        let project = Project(name: "test")
        try projectRepository.insert(project)

        let entry1 = TimeEntry(projectId: project.id, start: Date.from(year: 2024, month: 1, day: 1, hour: 9))
        let entry2 = TimeEntry(projectId: project.id, start: Date.from(year: 2024, month: 1, day: 1, hour: 10))
        try timeEntryRepository.insertRunning(entry: entry1)
        try timeEntryRepository.insertRunning(entry: entry2)

        try tracker.loadInitialState()

        XCTAssertNotNil(tracker.runningEntry)
        XCTAssertEqual(tracker.runningEntry?.id, entry2.id)
    }

    // MARK: - Timer Control

    func testStartTimer() throws {
        try tracker.loadInitialState()

        try tracker.startTimer()

        XCTAssertNotNil(tracker.runningEntry)
        XCTAssertTrue(tracker.isRunning)
        XCTAssertEqual(tracker.todaysEntries.count, 1)
    }

    func testStartTimerDoesNothingWhenAlreadyRunning() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()
        let firstEntry = tracker.runningEntry

        try tracker.startTimer()

        XCTAssertEqual(tracker.runningEntry?.id, firstEntry?.id)
        XCTAssertEqual(tracker.todaysEntries.count, 1)
    }

    func testStartTimerDoesNothingWithoutSelectedProject() throws {
        tracker.selectedProjectId = nil

        try tracker.startTimer()

        XCTAssertNil(tracker.runningEntry)
        XCTAssertFalse(tracker.isRunning)
    }

    func testStopTimer() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()

        try tracker.stopTimer()

        XCTAssertNil(tracker.runningEntry)
        XCTAssertFalse(tracker.isRunning)
        XCTAssertEqual(tracker.todaysEntries.count, 1)
        XCTAssertNotNil(tracker.todaysEntries[0].end)
    }

    func testStopTimerDoesNothingWhenNotRunning() throws {
        try tracker.loadInitialState()

        XCTAssertNoThrow(try tracker.stopTimer())
        XCTAssertNil(tracker.runningEntry)
    }

    func testElapsedSeconds() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()

        let now = tracker.runningEntry!.start.addingTimeInterval(120)
        let elapsed = tracker.elapsedSeconds(now: now)

        XCTAssertEqual(elapsed, 120)
    }

    func testElapsedSecondsReturnsZeroWhenNotRunning() throws {
        try tracker.loadInitialState()

        let elapsed = tracker.elapsedSeconds()

        XCTAssertEqual(elapsed, 0)
    }

    // MARK: - Project Management

    func testSelectProject() throws {
        try tracker.loadInitialState()
        let newProject = Project(name: "new")
        try projectRepository.insert(newProject)
        tracker.refreshProjects(keepSelection: true)

        tracker.selectProject(id: newProject.id)

        XCTAssertEqual(tracker.selectedProjectId, newProject.id)
    }

    func testCreateProject() throws {
        try tracker.loadInitialState()

        try tracker.createProject(name: "  New Project  ")

        XCTAssertEqual(tracker.projects.count, 2)
        XCTAssertTrue(tracker.projects.contains(where: { $0.name == "new project" }))
    }

    func testCreateProjectIgnoresEmptyName() throws {
        try tracker.loadInitialState()

        try tracker.createProject(name: "   ")

        XCTAssertEqual(tracker.projects.count, 1)
    }

    func testArchiveProject() throws {
        try tracker.loadInitialState()
        let projectId = tracker.projects[0].id
        let newProject = Project(name: "keeper")
        try projectRepository.insert(newProject)
        tracker.refreshProjects(keepSelection: true)

        try tracker.archiveProject(id: projectId)

        XCTAssertEqual(tracker.projects.count, 1)
        XCTAssertEqual(tracker.projects[0].name, "keeper")
    }

    func testArchiveProjectUpdatesSelection() throws {
        try tracker.loadInitialState()
        let projectToArchive = tracker.projects[0].id
        let newProject = Project(name: "next")
        try projectRepository.insert(newProject)
        tracker.refreshProjects(keepSelection: true)
        tracker.selectProject(id: projectToArchive)

        try tracker.archiveProject(id: projectToArchive)

        XCTAssertEqual(tracker.selectedProjectId, newProject.id)
    }

    func testProjectName() throws {
        try tracker.loadInitialState()
        let projectId = tracker.projects[0].id

        let name = tracker.projectName(for: projectId)

        XCTAssertEqual(name, "default")
    }

    func testProjectNameReturnsUnknownForMissing() throws {
        try tracker.loadInitialState()

        let name = tracker.projectName(for: "nonexistent")

        XCTAssertEqual(name, "unknown")
    }

    // MARK: - Entry Management

    func testUpdateEntry() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()
        try tracker.stopTimer()
        let entryId = tracker.todaysEntries[0].id
        let newStart = Date.from(year: 2024, month: 1, day: 1, hour: 8)
        let newEnd = Date.from(year: 2024, month: 1, day: 1, hour: 10)

        try tracker.updateEntry(id: entryId, start: newStart, end: newEnd, note: "updated")

        let entry = tracker.todaysEntries.first(where: { $0.id == entryId })
        XCTAssertEqual(entry?.start, newStart)
        XCTAssertEqual(entry?.end, newEnd)
        XCTAssertEqual(entry?.note, "updated")
    }

    func testUpdateEntryNormalizesEndBeforeStart() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()
        try tracker.stopTimer()
        let entryId = tracker.todaysEntries[0].id
        let start = Date.from(year: 2024, month: 1, day: 1, hour: 10)
        let endBeforeStart = Date.from(year: 2024, month: 1, day: 1, hour: 8)

        try tracker.updateEntry(id: entryId, start: start, end: endBeforeStart, note: nil)

        let entry = tracker.todaysEntries.first(where: { $0.id == entryId })
        XCTAssertEqual(entry?.end, start)
    }

    func testUpdateEntryClearsEmptyNote() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()
        try tracker.stopTimer()
        let entryId = tracker.todaysEntries[0].id

        try tracker.updateEntry(
            id: entryId,
            start: tracker.todaysEntries[0].start,
            end: tracker.todaysEntries[0].end,
            note: "   "
        )

        let entry = tracker.todaysEntries.first(where: { $0.id == entryId })
        XCTAssertNil(entry?.note)
    }

    func testDeleteEntry() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()
        try tracker.stopTimer()
        let entryId = tracker.todaysEntries[0].id

        try tracker.deleteEntry(id: entryId)

        XCTAssertTrue(tracker.todaysEntries.isEmpty)
    }

    func testDeleteRunningEntry() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()
        let entryId = tracker.runningEntry!.id

        try tracker.deleteEntry(id: entryId)

        XCTAssertNil(tracker.runningEntry)
        XCTAssertFalse(tracker.isRunning)
    }

    // MARK: - Reports

    func testDailyTotalsAfterWork() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()

        let now = tracker.runningEntry!.start.addingTimeInterval(3600)
        tracker.refreshReports(now: now)

        XCTAssertEqual(tracker.dailyTotals.count, 1)
        XCTAssertEqual(tracker.dailyTotals[0].seconds, 3600)
    }

    func testWeeklyTotalsAfterWork() throws {
        try tracker.loadInitialState()

        let entry = TimeEntry(
            projectId: tracker.projects[0].id,
            start: Date.from(year: 2024, month: 1, day: 3, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 3, hour: 11)
        )
        try timeEntryRepository.insertRunning(entry: entry)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date.from(year: 2024, month: 1, day: 7, hour: 12)

        tracker.refreshReports(now: now, calendar: calendar)

        let totalSeconds = tracker.weeklyTotals.reduce(0) { $0 + $1.seconds }
        XCTAssertEqual(totalSeconds, 2 * 3600)
    }

    // MARK: - Export

    func testExportCSV() throws {
        try tracker.loadInitialState()

        let entry = TimeEntry(
            projectId: tracker.projects[0].id,
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 10),
            note: "test"
        )
        try timeEntryRepository.insertRunning(entry: entry)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.csv")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let range = Date.from(year: 2024, month: 1, day: 1)..<Date.from(year: 2024, month: 1, day: 2)
        try tracker.exportCSV(range: range, to: tempURL)

        let content = try String(contentsOf: tempURL)
        XCTAssertTrue(content.contains("default"))
        XCTAssertTrue(content.contains("test"))
        XCTAssertTrue(content.contains("3600"))
    }

    // MARK: - Delegate

    func testDelegateCalledOnStartTimer() throws {
        let delegate = MockDelegate()
        tracker.delegate = delegate
        try tracker.loadInitialState()

        try tracker.startTimer()

        XCTAssertTrue(delegate.didUpdateCalled)
    }

    func testDelegateCalledOnStopTimer() throws {
        let delegate = MockDelegate()
        tracker.delegate = delegate
        try tracker.loadInitialState()
        try tracker.startTimer()
        delegate.didUpdateCalled = false

        try tracker.stopTimer()

        XCTAssertTrue(delegate.didUpdateCalled)
    }

    func testDelegateCalledOnUpdateEntry() throws {
        let delegate = MockDelegate()
        tracker.delegate = delegate
        try tracker.loadInitialState()
        try tracker.startTimer()
        try tracker.stopTimer()
        delegate.didUpdateCalled = false
        let entryId = tracker.todaysEntries[0].id

        try tracker.updateEntry(id: entryId, start: Date(), end: Date(), note: nil)

        XCTAssertTrue(delegate.didUpdateCalled)
    }

    func testDelegateCalledOnDeleteEntry() throws {
        let delegate = MockDelegate()
        tracker.delegate = delegate
        try tracker.loadInitialState()
        try tracker.startTimer()
        try tracker.stopTimer()
        delegate.didUpdateCalled = false
        let entryId = tracker.todaysEntries[0].id

        try tracker.deleteEntry(id: entryId)

        XCTAssertTrue(delegate.didUpdateCalled)
    }
}

// MARK: - Mock Delegate

private class MockDelegate: TimeTrackerDelegate {
    var didUpdateCalled = false

    func timeTrackerDidUpdate() {
        didUpdateCalled = true
    }
}
