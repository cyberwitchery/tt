import XCTest
import GRDB
@testable import tt

final class TrackerDerivationsTests: XCTestCase {
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

    // MARK: - startedAt

    func testStartedAtIsNilWithNoRunningEntry() throws {
        try tracker.loadInitialState()
        XCTAssertNil(tracker.startedAt)
    }

    func testStartedAtMatchesRunningEntryStart() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()
        XCTAssertNotNil(tracker.startedAt)
        XCTAssertEqual(tracker.startedAt, tracker.runningEntry?.start)
    }

    func testStartedAtClearedAfterStop() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()
        try tracker.stopTimer()
        XCTAssertNil(tracker.startedAt)
    }

    // MARK: - idleSeconds

    func testIdleSecondsNilWhenRunning() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()
        XCTAssertNil(tracker.idleSeconds())
    }

    func testIdleSecondsNilWithNoHistory() throws {
        try tracker.loadInitialState()
        XCTAssertNil(tracker.idleSeconds())
    }

    func testIdleSecondsMeasuresSinceLastEnd() throws {
        let project = Project(name: "default")
        try projectRepository.insert(project)

        let start = Date.from(year: 2025, month: 1, day: 1, hour: 9)
        let end = Date.from(year: 2025, month: 1, day: 1, hour: 10)
        try timeEntryRepository.insertRunning(entry: TimeEntry(projectId: project.id, start: start))
        // close that entry manually at `end`.
        var entry = try timeEntryRepository.fetchRunning()!
        entry.end = end
        try timeEntryRepository.update(entry)

        try tracker.loadInitialState()

        let now = end.addingTimeInterval(125) // 2m 5s later
        XCTAssertEqual(tracker.idleSeconds(now: now), 125)
    }

    func testIdleSecondsClampsToZeroWhenNowBeforeLastEnd() throws {
        let project = Project(name: "default")
        try projectRepository.insert(project)

        let end = Date.from(year: 2025, month: 1, day: 1, hour: 10)
        try timeEntryRepository.insertRunning(entry: TimeEntry(
            projectId: project.id,
            start: end.addingTimeInterval(-3600)
        ))
        var entry = try timeEntryRepository.fetchRunning()!
        entry.end = end
        try timeEntryRepository.update(entry)

        try tracker.loadInitialState()

        // clock skew: now earlier than last end.
        let now = end.addingTimeInterval(-60)
        XCTAssertEqual(tracker.idleSeconds(now: now), 0)
    }

    // MARK: - projectCompletedTotals

    func testProjectCompletedTotalsEmpty() throws {
        try tracker.loadInitialState()
        XCTAssertTrue(tracker.projectCompletedTotals.isEmpty)
    }

    func testProjectCompletedTotalsSumsEndedEntriesPerProject() throws {
        let a = Project(name: "a"); try projectRepository.insert(a)
        let b = Project(name: "b"); try projectRepository.insert(b)

        let day = Date.from(year: 2025, month: 1, day: 1)
        try insertEnded(projectId: a.id, start: day.addingTimeInterval(0), end: day.addingTimeInterval(3600))
        try insertEnded(projectId: a.id, start: day.addingTimeInterval(7200), end: day.addingTimeInterval(7200 + 1800))
        try insertEnded(projectId: b.id, start: day.addingTimeInterval(14400), end: day.addingTimeInterval(14400 + 600))

        try tracker.loadInitialState()

        XCTAssertEqual(tracker.projectCompletedTotals[a.id], 3600 + 1800)
        XCTAssertEqual(tracker.projectCompletedTotals[b.id], 600)
    }

    func testProjectCompletedTotalsExcludesRunningEntry() throws {
        let a = Project(name: "a"); try projectRepository.insert(a)

        try insertEnded(projectId: a.id,
                        start: Date.from(year: 2025, month: 1, day: 1, hour: 9),
                        end:   Date.from(year: 2025, month: 1, day: 1, hour: 10))
        try timeEntryRepository.insertRunning(entry: TimeEntry(
            projectId: a.id,
            start: Date.from(year: 2025, month: 1, day: 1, hour: 11)
        ))

        try tracker.loadInitialState()

        XCTAssertEqual(tracker.projectCompletedTotals[a.id], 3600)
    }

    // MARK: - projectAllTimeSeconds

    func testProjectAllTimeSecondsAddsLiveRunningContribution() throws {
        let a = Project(name: "a"); try projectRepository.insert(a)
        try insertEnded(projectId: a.id,
                        start: Date.from(year: 2025, month: 1, day: 1, hour: 9),
                        end:   Date.from(year: 2025, month: 1, day: 1, hour: 10))

        let runStart = Date.from(year: 2025, month: 1, day: 1, hour: 11)
        try timeEntryRepository.insertRunning(entry: TimeEntry(projectId: a.id, start: runStart))

        try tracker.loadInitialState()

        let now = runStart.addingTimeInterval(1800)
        XCTAssertEqual(tracker.projectAllTimeSeconds(for: a.id, now: now), 3600 + 1800)
    }

    func testProjectAllTimeSecondsForOtherProjectIgnoresRunning() throws {
        let a = Project(name: "a"); try projectRepository.insert(a)
        let b = Project(name: "b"); try projectRepository.insert(b)
        try insertEnded(projectId: a.id,
                        start: Date.from(year: 2025, month: 1, day: 1, hour: 9),
                        end:   Date.from(year: 2025, month: 1, day: 1, hour: 10))
        try timeEntryRepository.insertRunning(entry: TimeEntry(
            projectId: b.id,
            start: Date.from(year: 2025, month: 1, day: 1, hour: 11)
        ))

        try tracker.loadInitialState()

        let now = Date.from(year: 2025, month: 1, day: 1, hour: 11, minute: 30)
        // `a` has only the 1h ended entry; running is on `b`, so `a`'s total stays 3600.
        XCTAssertEqual(tracker.projectAllTimeSeconds(for: a.id, now: now), 3600)
    }

    // MARK: - updateEntry projectId reassignment

    func testUpdateEntryCanReassignProject() throws {
        let a = Project(name: "a"); try projectRepository.insert(a)
        let b = Project(name: "b"); try projectRepository.insert(b)

        let entry = TimeEntry(
            projectId: a.id,
            start: Date.from(year: 2025, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2025, month: 1, day: 1, hour: 10)
        )
        try timeEntryRepository.insertRunning(entry: entry) // ended already

        try tracker.loadInitialState()

        try tracker.updateEntry(
            id: entry.id,
            start: entry.start,
            end: entry.end,
            note: nil,
            projectId: b.id
        )

        let reloaded = try timeEntryRepository.get(id: entry.id)
        XCTAssertEqual(reloaded?.projectId, b.id)
    }

    func testUpdateEntryIgnoresUnknownProjectId() throws {
        let a = Project(name: "a"); try projectRepository.insert(a)
        let entry = TimeEntry(
            projectId: a.id,
            start: Date.from(year: 2025, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2025, month: 1, day: 1, hour: 10)
        )
        try timeEntryRepository.insertRunning(entry: entry)

        try tracker.loadInitialState()

        try tracker.updateEntry(
            id: entry.id,
            start: entry.start,
            end: entry.end,
            note: nil,
            projectId: "nope"
        )

        let reloaded = try timeEntryRepository.get(id: entry.id)
        XCTAssertEqual(reloaded?.projectId, a.id)
    }

    // MARK: - helpers

    private func insertEnded(projectId: String, start: Date, end: Date) throws {
        let entry = TimeEntry(projectId: projectId, start: start, end: end)
        try dbQueue.write { db in try entry.insert(db) }
    }

    // MARK: - Selected Day

    private var calendar: Calendar { Calendar.current }

    private func startOfDay(daysAgo: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -daysAgo, to: today)!
    }

    private func time(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfDay(daysAgo: daysAgo))!
    }

    @discardableResult
    private func insert(daysAgo: Int, from: Int, to: Int?) throws -> TimeEntry {
        let entry = TimeEntry(
            projectId: tracker.projects[0].id,
            start: time(daysAgo: daysAgo, hour: from),
            end: to.map { time(daysAgo: daysAgo, hour: $0) }
        )
        try timeEntryRepository.insertRunning(entry: entry)
        return entry
    }

    func testSelectedDayDefaultsToToday() throws {
        try tracker.loadInitialState()

        XCTAssertTrue(tracker.isViewingToday)
        XCTAssertEqual(tracker.selectedDay(), startOfDay(daysAgo: 0))
    }

    func testStepDayBackShowsThatDaysEntries() throws {
        try tracker.loadInitialState()
        let yesterday = try insert(daysAgo: 1, from: 9, to: 10)
        let today = try insert(daysAgo: 0, from: 9, to: 10)
        tracker.refreshEntries()

        tracker.stepDay(by: -1)

        XCTAssertFalse(tracker.isViewingToday)
        XCTAssertEqual(tracker.selectedDay(), startOfDay(daysAgo: 1))
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [yesterday.id])
        XCTAssertEqual(tracker.todaysEntries.map(\.id), [today.id])
    }

    func testStepDayForwardIsClampedToToday() throws {
        try tracker.loadInitialState()

        tracker.stepDay(by: 1)
        XCTAssertEqual(tracker.dayOffset, 0)

        tracker.stepDay(by: -2)
        tracker.stepDay(by: 5)
        XCTAssertEqual(tracker.dayOffset, 0)
        XCTAssertTrue(tracker.isViewingToday)
    }

    func testGoToTodayRestoresTodaysEntries() throws {
        try tracker.loadInitialState()
        try insert(daysAgo: 2, from: 9, to: 10)
        let today = try insert(daysAgo: 0, from: 9, to: 10)
        tracker.refreshEntries()

        tracker.stepDay(by: -2)
        tracker.goToToday()

        XCTAssertTrue(tracker.isViewingToday)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [today.id])
    }

    func testTodaysEntriesStayOnTodayWhileBrowsingBack() throws {
        try tracker.loadInitialState()
        try insert(daysAgo: 3, from: 9, to: 17)
        let today = try insert(daysAgo: 0, from: 9, to: 10)
        tracker.refreshEntries()

        tracker.stepDay(by: -3)

        XCTAssertEqual(tracker.todaysEntries.map(\.id), [today.id])
    }

    func testStartTimerReturnsToToday() throws {
        try tracker.loadInitialState()
        tracker.stepDay(by: -1)

        try tracker.startTimer()

        XCTAssertTrue(tracker.isViewingToday)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [tracker.runningEntry!.id])
    }

    func testStopTimerReturnsToToday() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()
        let entryId = tracker.runningEntry!.id
        tracker.stepDay(by: -2)

        try tracker.stopTimer()

        XCTAssertTrue(tracker.isViewingToday)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entryId])
    }

    func testDailyTotalsFollowTheSelectedDay() throws {
        try tracker.loadInitialState()
        try insert(daysAgo: 1, from: 9, to: 11)
        try insert(daysAgo: 0, from: 9, to: 10)
        tracker.refreshReports()

        XCTAssertEqual(tracker.dailyTotals.first?.seconds, 3600)

        tracker.stepDay(by: -1)

        XCTAssertEqual(tracker.dailyTotals.first?.seconds, 2 * 3600)
    }

    func testEntrySpanningMidnightIsClippedToEachDay() throws {
        try tracker.loadInitialState()
        let start = time(daysAgo: 1, hour: 23)
        let end = time(daysAgo: 0, hour: 1)
        let entry = TimeEntry(projectId: tracker.projects[0].id, start: start, end: end)
        try timeEntryRepository.insertRunning(entry: entry)
        tracker.refreshEntries()
        tracker.refreshReports()

        let midnight = startOfDay(daysAgo: 0)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id])
        XCTAssertEqual(tracker.dailyTotals.first?.seconds, Int(end.timeIntervalSince(midnight)))

        tracker.stepDay(by: -1)

        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id])
        XCTAssertEqual(tracker.dailyTotals.first?.seconds, Int(midnight.timeIntervalSince(start)))
    }

    func testDeleteEntryOnAPastDayKeepsThatDaySelected() throws {
        try tracker.loadInitialState()
        let kept = try insert(daysAgo: 1, from: 9, to: 10)
        let removed = try insert(daysAgo: 1, from: 11, to: 12)
        tracker.refreshEntries()
        tracker.stepDay(by: -1)

        try tracker.deleteEntry(id: removed.id)

        XCTAssertFalse(tracker.isViewingToday)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [kept.id])
        XCTAssertEqual(tracker.dailyTotals.first?.seconds, 3600)
    }

    func testEditingAPastEntryLeavesItOnItsOwnDay() throws {
        try tracker.loadInitialState()
        let entry = try insert(daysAgo: 1, from: 9, to: 10)
        tracker.refreshEntries()
        tracker.stepDay(by: -1)

        let fields = EntryEditor.withEnd(
            EntryEditor.fields(start: entry.start, end: entry.end),
            seconds: 11 * 3600
        )
        let (start, end) = EntryEditor.resolve(fields, baseDate: entry.start)
        try tracker.updateEntry(id: entry.id, start: start, end: end, note: "fixed")

        XCTAssertFalse(tracker.isViewingToday)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id])
        XCTAssertEqual(tracker.visibleEntries.first?.note, "fixed")
        XCTAssertEqual(tracker.dailyTotals.first?.seconds, 2 * 3600)
        XCTAssertTrue(tracker.todaysEntries.isEmpty)
    }

    func testRunningEntryStartedYesterdayShowsOnBothDays() throws {
        try tracker.loadInitialState()
        let entry = TimeEntry(projectId: tracker.projects[0].id, start: time(daysAgo: 1, hour: 23))
        try timeEntryRepository.insertRunning(entry: entry)
        tracker.refreshEntries()

        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id])

        tracker.stepDay(by: -1)

        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id])
    }

    // MARK: - Day Totals

    private func insertSpanningMidnight() throws -> (start: Date, end: Date) {
        let start = time(daysAgo: 1, hour: 23)
        let end = time(daysAgo: 0, hour: 1)
        let entry = TimeEntry(projectId: tracker.projects[0].id, start: start, end: end)
        try timeEntryRepository.insertRunning(entry: entry)
        return (start, end)
    }

    func testVisibleDayTotalClipsAnEntrySpanningMidnightToTheSelectedDay() throws {
        try tracker.loadInitialState()
        let (start, end) = try insertSpanningMidnight()
        tracker.refreshEntries()

        let midnight = startOfDay(daysAgo: 0)
        XCTAssertEqual(tracker.visibleDayTotalSeconds(), Int(end.timeIntervalSince(midnight)))

        tracker.stepDay(by: -1)

        XCTAssertEqual(tracker.visibleDayTotalSeconds(), Int(midnight.timeIntervalSince(start)))
    }

    func testTodayTotalClipsAnEntrySpanningMidnightToToday() throws {
        try tracker.loadInitialState()
        let (_, end) = try insertSpanningMidnight()
        tracker.refreshEntries()

        XCTAssertEqual(tracker.todayTotalSeconds(), Int(end.timeIntervalSince(startOfDay(daysAgo: 0))))
    }

    func testTodayTotalStaysOnTodayWhileTheHeaderTotalFollowsTheSelection() throws {
        try tracker.loadInitialState()
        try insert(daysAgo: 1, from: 9, to: 12)
        try insert(daysAgo: 0, from: 9, to: 10)
        tracker.refreshEntries()

        XCTAssertEqual(tracker.todayTotalSeconds(), 3600)
        XCTAssertEqual(tracker.visibleDayTotalSeconds(), 3600)

        tracker.stepDay(by: -1)

        XCTAssertEqual(tracker.todayTotalSeconds(), 3600)
        XCTAssertEqual(tracker.visibleDayTotalSeconds(), 3 * 3600)
    }

    // MARK: - Midnight Rollover

    func testRollOverMovesTheListOntoTheNewDay() throws {
        try tracker.loadInitialState()
        try insert(daysAgo: 1, from: 9, to: 10)
        tracker.refreshEntries(now: time(daysAgo: 1, hour: 23))
        XCTAssertEqual(tracker.visibleEntries.count, 1)

        XCTAssertTrue(tracker.rollOverIfNeeded(now: time(daysAgo: 0, hour: 0, minute: 30)))

        XCTAssertTrue(tracker.isViewingToday)
        XCTAssertEqual(tracker.selectedDay(), startOfDay(daysAgo: 0))
        XCTAssertTrue(tracker.visibleEntries.isEmpty)
        XCTAssertTrue(tracker.todaysEntries.isEmpty)
    }

    func testRollOverHoldsABrowsedDayOnItsOwnDate() throws {
        try tracker.loadInitialState()
        let older = try insert(daysAgo: 2, from: 9, to: 10)
        tracker.stepDay(by: -1)
        tracker.refreshEntries(now: time(daysAgo: 1, hour: 23))
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [older.id])

        XCTAssertTrue(tracker.rollOverIfNeeded(now: time(daysAgo: 0, hour: 0, minute: 30)))

        XCTAssertEqual(tracker.dayOffset, -2)
        XCTAssertEqual(tracker.selectedDay(), startOfDay(daysAgo: 2))
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [older.id])
    }

    func testRollOverDoesNothingUntilTheDayActuallyChanges() throws {
        XCTAssertFalse(tracker.rollOverIfNeeded(now: time(daysAgo: 0, hour: 9)))

        try tracker.loadInitialState()
        tracker.refreshEntries(now: time(daysAgo: 0, hour: 9))

        XCTAssertFalse(tracker.rollOverIfNeeded(now: time(daysAgo: 0, hour: 23)))
    }
}
