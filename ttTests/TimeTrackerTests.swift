import XCTest
import Combine
import GRDB
@testable import tt

final class TimeTrackerTests: TrackerTestCase {
    func testCreatedProjectsReturnTheirOwnIDsEvenWithDuplicateNames() throws {
        try tracker.loadInitialState()
        let first = try XCTUnwrap(tracker.createProject(name: " Same "))
        let second = try XCTUnwrap(tracker.createProject(name: "same"))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.name, "same")
        XCTAssertEqual(second.name, "same")
        XCTAssertTrue(tracker.projects.contains { $0.id == second.id })
        XCTAssertNil(try tracker.createProject(name: "  "))
    }

    func testUpdatingAnUnrelatedEntryDoesNotCloseOtherRunningEntries() throws {
        try tracker.loadInitialState()
        let project = try XCTUnwrap(tracker.projects.first)
        let start = Date.from(year: 2026, month: 1, day: 1, hour: 9)
        let first = TimeEntry(projectId: project.id, start: start)
        let second = TimeEntry(projectId: project.id, start: start + 60)
        let ended = TimeEntry(projectId: project.id, start: start - 3600, end: start)
        for entry in [first, second, ended] { try timeEntryRepository.insertRunning(entry: entry) }
        try tracker.updateEntry(id: ended.id, start: ended.start, end: ended.end, note: "edited")
        XCTAssertNil(try timeEntryRepository.get(id: first.id)?.end)
        XCTAssertNil(try timeEntryRepository.get(id: second.id)?.end)
        XCTAssertEqual(try timeEntryRepository.get(id: ended.id)?.note, "edited")
    }

    // MARK: - Initial Load

    func testInitialLoadUsesTheInjectedDayForEntriesAndReports() throws {
        clock.calendar = Calendar(identifier: .gregorian)
        clock.calendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        clock.now = Date.from(year: 2026, month: 1, day: 1, hour: 12)
        let project = Project(name: "test")
        try projectRepository.insert(project)
        let entry = TimeEntry(
            projectId: project.id,
            start: Date.from(year: 2026, month: 1, day: 1, hour: 10),
            end: Date.from(year: 2026, month: 1, day: 1, hour: 11)
        )
        try timeEntryRepository.insertRunning(entry: entry)

        try tracker.loadInitialState()

        XCTAssertEqual(tracker.selectedDay(), Date.from(year: 2026, month: 1, day: 1, hour: 10))
        XCTAssertEqual(tracker.todaysEntries.map(\.id), [entry.id])
        XCTAssertEqual(tracker.projectTotalsForSelectedDay.map(\.seconds), [3600])
        XCTAssertEqual(tracker.recentDayTotals().last?.seconds, 3600)
    }

    func testTimerUsesTheInjectedClockForStartAndStop() throws {
        clock.now = Date.from(year: 2026, month: 1, day: 1, hour: 9)
        try tracker.loadInitialState()
        try tracker.startTimer()
        let id = try XCTUnwrap(tracker.runningEntry?.id)
        XCTAssertEqual(tracker.startedAt, clock.now)

        clock.now = clock.now.addingTimeInterval(90)
        XCTAssertEqual(tracker.elapsedSeconds(), 90)
        try tracker.stopTimer()

        XCTAssertEqual(try timeEntryRepository.get(id: id)?.end, clock.now)
    }

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
        clock.now = now
        let elapsed = tracker.elapsedSeconds()

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
        try tracker.refreshProjects()

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
        try tracker.refreshProjects()

        try tracker.archiveProject(id: projectId)

        XCTAssertEqual(tracker.projects.count, 1)
        XCTAssertEqual(tracker.projects[0].name, "keeper")
    }

    func testArchiveProjectUpdatesSelection() throws {
        try tracker.loadInitialState()
        let projectToArchive = tracker.projects[0].id
        let newProject = Project(name: "next")
        try projectRepository.insert(newProject)
        try tracker.refreshProjects()
        tracker.selectProject(id: projectToArchive)

        try tracker.archiveProject(id: projectToArchive)

        XCTAssertEqual(tracker.selectedProjectId, newProject.id)
    }

    func testArchivingAnotherProjectKeepsTheSelectedProject() throws {
        try tracker.loadInitialState()
        try tracker.createProject(name: "selected")
        try tracker.createProject(name: "archived")
        let selected = try XCTUnwrap(tracker.projects.first { $0.name == "selected" })
        let archived = try XCTUnwrap(tracker.projects.first { $0.name == "archived" })
        tracker.selectProject(id: selected.id)
        try tracker.archiveProject(id: archived.id)
        XCTAssertEqual(tracker.selectedProjectId, selected.id)
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

    func testArchivedProjectKeepsItsName() throws {
        try tracker.loadInitialState()
        let project = Project(name: "client")
        try projectRepository.insert(project)
        try tracker.refreshProjects()
        let start = Date.from(year: 2024, month: 6, day: 15, hour: 9)
        try timeEntryRepository.insertRunning(
            entry: TimeEntry(projectId: project.id, start: start, end: start.addingTimeInterval(3600))
        )

        try tracker.archiveProject(id: project.id)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        clock.now = start.addingTimeInterval(7200)
        clock.calendar = calendar
        try tracker.refreshReports()

        XCTAssertEqual(tracker.projectName(for: project.id), "client")
        XCTAssertEqual(tracker.projectTotalsForSelectedDay.map(\.name), ["client"])
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

        let entry = try timeEntryRepository.get(id: entryId)
        XCTAssertEqual(entry?.id, entryId)
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

        let entry = try timeEntryRepository.get(id: entryId)
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
        let projectId = tracker.projects[0].id
        let start = Date.from(year: 2024, month: 6, day: 15, hour: 14, minute: 0)
        let entry = TimeEntry(projectId: projectId, start: start)
        try timeEntryRepository.insertRunning(entry: entry)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = start.addingTimeInterval(42)
        clock.now = now
        clock.calendar = calendar
        try tracker.refreshReports()

        XCTAssertEqual(tracker.projectTotalsForSelectedDay.count, 1)
        XCTAssertEqual(tracker.projectTotalsForSelectedDay[0].seconds, 42)
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

        clock.now = now
        clock.calendar = calendar
        try tracker.refreshReports()

        let totalSeconds = tracker.recentDayTotals().reduce(0) { $0 + $1.seconds }
        XCTAssertEqual(totalSeconds, 2 * 3600)
    }

    func testWeeklyTotalsViewedOnADayWithoutAMidnightStartAtMidnightSixDaysBack() throws {
        try tracker.loadInitialState()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santiago")!
        func santiago(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2024, month: 9, day: day, hour: hour, minute: minute))!
        }
        let entry = TimeEntry(projectId: tracker.projects[0].id, start: santiago(2, 0, 30), end: santiago(2, 0, 45))
        try timeEntryRepository.insertRunning(entry: entry)

        let now = santiago(8, 12)
        clock.now = now
        clock.calendar = calendar
        try tracker.refreshReports()

        XCTAssertEqual(tracker.recentDayTotals().first?.seconds, 15 * 60)
    }

    func testWeeklyTotalsCountARunningTimerUpToEachRead() throws {
        try tracker.loadInitialState()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func june(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            Date.from(year: 2024, month: 6, day: day, hour: hour, minute: minute)
        }
        let hour = 3600
        let day = 24 * hour
        let timers: [(start: Date, refreshed: Date, read: Date, days: [Int])] = [
            (june(15, 9), june(15, 9), june(15, 11, 30), [0, 0, 0, 0, 0, 0, 2 * hour + 30 * 60]),
            (june(14, 23), june(14, 23), june(15, 0, 30), [0, 0, 0, 0, 0, hour, 30 * 60]),
            (june(5, 12), june(15, 8), june(15, 10), [day, day, day, day, day, day, 10 * hour]),
        ]
        for (start, refreshed, read, days) in timers {
            let entry = TimeEntry(projectId: tracker.projects[0].id, start: start)
            try timeEntryRepository.insertRunning(entry: entry)
            clock.now = refreshed
            clock.calendar = calendar
            try tracker.refreshReports()

            clock.now = read
            XCTAssertEqual(tracker.recentDayTotals().map(\.seconds), days, "\(start)")
            clock.now = read.addingTimeInterval(3600)
            let hourLater = tracker.recentDayTotals()
            XCTAssertEqual(hourLater.map(\.seconds).reduce(0, +), days.reduce(0, +) + hour, "\(start)")

            try timeEntryRepository.delete(id: entry.id)
        }
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

    // MARK: - Observation

    func testObserversNotifiedOnStartTimer() throws {
        var notifications = 0
        let observation = tracker.objectWillChange.sink { notifications += 1 }
        defer { observation.cancel() }
        try tracker.loadInitialState()

        try tracker.startTimer()

        XCTAssertGreaterThan(notifications, 0)
    }

    func testObserversNotifiedOnStopTimer() throws {
        var notifications = 0
        let observation = tracker.objectWillChange.sink { notifications += 1 }
        defer { observation.cancel() }
        try tracker.loadInitialState()
        try tracker.startTimer()
        notifications = 0

        try tracker.stopTimer()

        XCTAssertGreaterThan(notifications, 0)
    }

    func testObserversNotifiedOnUpdateEntry() throws {
        var notifications = 0
        let observation = tracker.objectWillChange.sink { notifications += 1 }
        defer { observation.cancel() }
        try tracker.loadInitialState()
        try tracker.startTimer()
        try tracker.stopTimer()
        notifications = 0
        let entryId = tracker.todaysEntries[0].id

        try tracker.updateEntry(id: entryId, start: Date(), end: Date(), note: nil)

        XCTAssertGreaterThan(notifications, 0)
    }

    func testObserversNotifiedOnDeleteEntry() throws {
        var notifications = 0
        let observation = tracker.objectWillChange.sink { notifications += 1 }
        defer { observation.cancel() }
        try tracker.loadInitialState()
        try tracker.startTimer()
        try tracker.stopTimer()
        notifications = 0
        let entryId = tracker.todaysEntries[0].id

        try tracker.deleteEntry(id: entryId)

        XCTAssertGreaterThan(notifications, 0)
    }
}
