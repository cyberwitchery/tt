import XCTest
import GRDB
@testable import tt

final class TrackerDerivationsTests: TrackerTestCase {
    func testCommittedTimerIsCountedEvenWhenTheFirstReportLoadFails() throws {
        clock.now = Date.from(year: 2026, month: 1, day: 2, hour: 12)
        let project = Project(name: "tracked")
        let history = Project(name: "history")
        try projectRepository.insert(project)
        try projectRepository.insert(history)
        try timeEntryRepository.insertRunning(entry: TimeEntry(projectId: history.id, start: clock.now - 10 * 86400, end: clock.now - 10 * 86400 + 3600))
        let failReports = DatabaseFunction("strftime", argumentCount: 2) { _ -> String? in
            throw DatabaseError(resultCode: .SQLITE_ERROR, message: "injected report failure")
        }
        try dbQueue.write { $0.add(function: failReports) }
        XCTAssertThrowsError(try tracker.loadInitialState())
        XCTAssertThrowsError(try tracker.startTimer())
        clock.now = clock.now.addingTimeInterval(120)
        XCTAssertThrowsError(try tracker.stopTimer())
        clock.now = clock.now.addingTimeInterval(60)

        XCTAssertNil(tracker.runningEntry)
        XCTAssertEqual(tracker.todayTotalSeconds(), 120)
        XCTAssertEqual(tracker.visibleDayTotalSeconds(), 120)
        XCTAssertEqual(tracker.recentTotalSeconds(), 120)
        XCTAssertEqual(tracker.projectAllTimeSeconds(for: project.id), 120)
    }

    func testKnownTimerWritesAcrossMidnightRemainClippedWhenReportsFail() throws {
        for action in ["start", "stop"] {
            let clock = TestClock()
            clock.calendar = Calendar(identifier: .gregorian)
            clock.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            clock.now = Date.from(year: 2026, month: 1, day: 2, hour: 23, minute: 59)
            let database = try TestDatabase.makeInMemory()
            let entries = TimeEntryRepository(dbQueue: database)
            let tracker = TimeTracker(projectRepository: ProjectRepository(dbQueue: database), timeEntryRepository: entries, days: clock.days)
            try tracker.loadInitialState()
            let projectId = tracker.projects[0].id
            try entries.insertRunning(entry: TimeEntry(projectId: projectId, start: clock.now - 10 * 86400, end: clock.now - 10 * 86400 + 3600))
            try tracker.refreshReports()
            if action == "stop" { try tracker.startTimer() }
            let selected = tracker.selectedDay()
            clock.now = clock.now.addingTimeInterval(120)
            let failReports = DatabaseFunction("strftime", argumentCount: 2) { _ -> String? in
                throw DatabaseError(resultCode: .SQLITE_ERROR, message: "injected report failure")
            }
            try database.write { $0.add(function: failReports) }
            if action == "stop" { XCTAssertThrowsError(try tracker.stopTimer()) }
            else { XCTAssertThrowsError(try tracker.startTimer()) }
            clock.now = clock.now.addingTimeInterval(60)

            XCTAssertEqual(tracker.selectedDay(), selected, action)
            XCTAssertEqual(tracker.todayTotalSeconds(), 60, action)
            XCTAssertEqual(tracker.visibleDayTotalSeconds(), action == "stop" ? 60 : 0, action)
            XCTAssertEqual(tracker.recentTotalSeconds(), action == "stop" ? 120 : 60, action)
            XCTAssertEqual(tracker.projectAllTimeSeconds(for: projectId), action == "stop" ? 3720 : 3660, action)
        }
    }

    func testEveryRefreshPathKeepsABrowsedDateAcrossMidnight() throws {
        for action in ["entries", "reports", "create", "archive"] {
            let clock = TestClock()
            clock.calendar = Calendar(identifier: .gregorian)
            clock.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            clock.now = Date.from(year: 2026, month: 1, day: 2, hour: 23)
            let database = try TestDatabase.makeInMemory()
            let projects = ProjectRepository(dbQueue: database)
            let entries = TimeEntryRepository(dbQueue: database)
            let tracker = TimeTracker(projectRepository: projects, timeEntryRepository: entries, days: clock.days)
            try tracker.loadInitialState()
            let archive = Project(name: "archive")
            try projects.insert(archive)
            let start = Date.from(year: 2026, month: 1, day: 1, hour: 9)
            let entry = TimeEntry(projectId: tracker.projects[0].id, start: start, end: start + 3600)
            try entries.insertRunning(entry: entry)
            try tracker.stepDay(by: -1)
            let selected = tracker.selectedDay()
            clock.now = Date.from(year: 2026, month: 1, day: 3, hour: 0, minute: 30)

            switch action {
            case "entries": try tracker.refreshEntries()
            case "reports": try tracker.refreshReports()
            case "create": try tracker.createProject(name: "new")
            default: try tracker.archiveProject(id: archive.id)
            }

            XCTAssertEqual(tracker.selectedDay(), selected, action)
            XCTAssertEqual(tracker.dayOffset, -2, action)
            XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id], action)
            XCTAssertEqual(tracker.visibleDayTotalSeconds(), 3600, action)
            XCTAssertFalse(try tracker.rollOverIfNeeded(), action)
        }
    }

    func testCommittedEntryChangesStayReflectedWhenReportReadsFail() throws {
        for action in ["start", "stop", "edit", "delete"] {
            let clock = TestClock()
            clock.calendar = Calendar(identifier: .gregorian)
            clock.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            clock.now = Date.from(year: 2026, month: 1, day: 2, hour: 12)
            let database = try TestDatabase.makeInMemory()
            let projects = ProjectRepository(dbQueue: database)
            let entries = TimeEntryRepository(dbQueue: database)
            let tracker = TimeTracker(projectRepository: projects, timeEntryRepository: entries, days: clock.days)
            try tracker.loadInitialState()
            let projectId = tracker.projects[0].id
            let history = Project(name: "history")
            try projects.insert(history)
            try entries.insertRunning(entry: TimeEntry(projectId: history.id, start: clock.now - 10 * 86400, end: clock.now - 10 * 86400 + 3600))
            try tracker.refreshProjects()
            if action != "start" {
                try tracker.startTimer()
                clock.now = clock.now.addingTimeInterval(120)
                try tracker.refreshEntries()
            }
            let running = tracker.runningEntry
            let failReports = DatabaseFunction("strftime", argumentCount: 2) { _ -> String? in
                throw DatabaseError(resultCode: .SQLITE_ERROR, message: "injected report failure")
            }
            try database.write { $0.add(function: failReports) }

            switch action {
            case "start": XCTAssertThrowsError(try tracker.startTimer())
            case "stop": XCTAssertThrowsError(try tracker.stopTimer())
            case "edit":
                let entry = try XCTUnwrap(running)
                XCTAssertThrowsError(try tracker.updateEntry(id: entry.id, start: entry.start, end: clock.now, note: "closed"))
            default: XCTAssertThrowsError(try tracker.deleteEntry(id: XCTUnwrap(running).id))
            }

            let expected = action == "start" ? 60 : (action == "delete" ? 0 : 120)
            if let running, action != "delete" {
                XCTAssertEqual(try entries.get(id: running.id)?.end, clock.now, action)
            }
            clock.now = clock.now.addingTimeInterval(60)
            XCTAssertEqual(tracker.todayTotalSeconds(), expected, action)
            XCTAssertEqual(tracker.visibleDayTotalSeconds(), expected, action)
            XCTAssertEqual(tracker.recentTotalSeconds(), expected, action)
            XCTAssertEqual(tracker.projectTotalsForSelectedDay.reduce(0) { $0 + $1.seconds }, expected, action)
            XCTAssertEqual(tracker.projectAllTimeSeconds(for: projectId), expected, action)
            XCTAssertEqual(tracker.projectAllTimeSeconds(for: history.id), 3600, action)
            if action != "start" {
                XCTAssertNil(tracker.runningEntry, action)
                XCTAssertTrue(tracker.visibleEntries.allSatisfy { $0.end != nil }, action)
                XCTAssertTrue(tracker.todaysEntries.allSatisfy { $0.end != nil }, action)
            }
        }
    }

    func testFailedMidnightRefreshDoesNotApplyTheDayShiftAgainOnRetry() throws {
        clock.calendar = Calendar(identifier: .gregorian)
        clock.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        clock.now = Date.from(year: 2026, month: 1, day: 2, hour: 23)
        try tracker.loadInitialState()
        let start = Date.from(year: 2026, month: 1, day: 1, hour: 9)
        let entry = TimeEntry(projectId: tracker.projects[0].id, start: start, end: start + 3600)
        try timeEntryRepository.insertRunning(entry: entry)
        try tracker.stepDay(by: -1)
        let selected = tracker.selectedDay()
        try dbQueue.write { try $0.execute(sql: "ALTER TABLE time_entries RENAME TO unavailable_entries") }
        clock.now = Date.from(year: 2026, month: 1, day: 3, hour: 0, minute: 30)

        for _ in 0..<2 {
            XCTAssertThrowsError(try tracker.rollOverIfNeeded())
            XCTAssertEqual(tracker.dayOffset, -1)
            XCTAssertEqual(tracker.selectedDay(), selected)
            XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id])
            XCTAssertEqual(tracker.visibleDayTotalSeconds(), 3600)
        }

        try dbQueue.write { try $0.execute(sql: "ALTER TABLE unavailable_entries RENAME TO time_entries") }
        XCTAssertTrue(try tracker.rollOverIfNeeded())
        XCTAssertEqual(tracker.dayOffset, -2)
        XCTAssertEqual(tracker.selectedDay(), selected)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id])
        XCTAssertFalse(try tracker.rollOverIfNeeded())
    }

    func testFailedReportsDoNotPublishTheNavigationTargetEntries() throws {
        clock.calendar = Calendar(identifier: .gregorian)
        clock.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        clock.now = Date.from(year: 2026, month: 1, day: 2, hour: 12)
        try tracker.loadInitialState()
        let today = TimeEntry(projectId: tracker.projects[0].id, start: clock.now - 3600, end: clock.now)
        let yesterday = TimeEntry(projectId: tracker.projects[0].id, start: clock.now - 86400, end: clock.now - 86400 + 1800)
        for entry in [today, yesterday] { try timeEntryRepository.insertRunning(entry: entry) }
        try tracker.refreshEntries()
        try tracker.refreshReports()
        let selected = tracker.selectedDay()
        let totals = tracker.projectTotalsForSelectedDay
        let recent = tracker.recentDayTotals()
        let failReports = DatabaseFunction("strftime", argumentCount: 2) { _ -> String? in
            throw DatabaseError(resultCode: .SQLITE_ERROR, message: "injected report failure")
        }
        try dbQueue.write { $0.add(function: failReports) }

        XCTAssertThrowsError(try tracker.stepDay(by: -1))
        XCTAssertTrue(tracker.isViewingToday)
        XCTAssertEqual(tracker.dayOffset, 0)
        XCTAssertEqual(tracker.selectedDay(), selected)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [today.id])
        XCTAssertEqual(tracker.todaysEntries.map(\.id), [today.id])
        XCTAssertEqual(tracker.visibleDayTotalSeconds(), 3600)
        XCTAssertEqual(tracker.projectTotalsForSelectedDay, totals)
        XCTAssertEqual(tracker.recentDayTotals(), recent)
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
        clock.now = now
        XCTAssertEqual(tracker.idleSeconds(), 125)
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
        clock.now = now
        XCTAssertEqual(tracker.idleSeconds(), 0)
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
        clock.now = now
        XCTAssertEqual(tracker.projectAllTimeSeconds(for: a.id), 3600 + 1800)
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
        clock.now = now
        XCTAssertEqual(tracker.projectAllTimeSeconds(for: a.id), 3600)
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
        try tracker.refreshEntries()

        try tracker.stepDay(by: -1)

        XCTAssertFalse(tracker.isViewingToday)
        XCTAssertEqual(tracker.selectedDay(), startOfDay(daysAgo: 1))
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [yesterday.id])
        XCTAssertEqual(tracker.todaysEntries.map(\.id), [today.id])
    }

    func testStepDayForwardIsClampedToToday() throws {
        try tracker.loadInitialState()

        try tracker.stepDay(by: 1)
        XCTAssertEqual(tracker.dayOffset, 0)

        try tracker.stepDay(by: -2)
        try tracker.stepDay(by: 5)
        XCTAssertEqual(tracker.dayOffset, 0)
        XCTAssertTrue(tracker.isViewingToday)
    }

    func testGoToTodayRestoresTodaysEntries() throws {
        try tracker.loadInitialState()
        try insert(daysAgo: 2, from: 9, to: 10)
        let today = try insert(daysAgo: 0, from: 9, to: 10)
        try tracker.refreshEntries()

        try tracker.stepDay(by: -2)
        try tracker.goToToday()

        XCTAssertTrue(tracker.isViewingToday)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [today.id])
    }

    func testTodaysEntriesStayOnTodayWhileBrowsingBack() throws {
        try tracker.loadInitialState()
        try insert(daysAgo: 3, from: 9, to: 17)
        let today = try insert(daysAgo: 0, from: 9, to: 10)
        try tracker.refreshEntries()

        try tracker.stepDay(by: -3)

        XCTAssertEqual(tracker.todaysEntries.map(\.id), [today.id])
    }

    func testStartTimerReturnsToToday() throws {
        try tracker.loadInitialState()
        try tracker.stepDay(by: -1)

        try tracker.startTimer()

        XCTAssertTrue(tracker.isViewingToday)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [tracker.runningEntry!.id])
    }

    func testStopTimerReturnsToToday() throws {
        try tracker.loadInitialState()
        try tracker.startTimer()
        let entryId = tracker.runningEntry!.id
        try tracker.stepDay(by: -2)

        try tracker.stopTimer()

        XCTAssertTrue(tracker.isViewingToday)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entryId])
    }

    func testDailyTotalsFollowTheSelectedDay() throws {
        try tracker.loadInitialState()
        try insert(daysAgo: 1, from: 9, to: 11)
        try insert(daysAgo: 0, from: 9, to: 10)
        try tracker.refreshReports()

        XCTAssertEqual(tracker.projectTotalsForSelectedDay.first?.seconds, 3600)

        try tracker.stepDay(by: -1)

        XCTAssertEqual(tracker.projectTotalsForSelectedDay.first?.seconds, 2 * 3600)
    }

    func testEntrySpanningMidnightIsClippedToEachDay() throws {
        try tracker.loadInitialState()
        let start = time(daysAgo: 1, hour: 23)
        let end = time(daysAgo: 0, hour: 1)
        let entry = TimeEntry(projectId: tracker.projects[0].id, start: start, end: end)
        try timeEntryRepository.insertRunning(entry: entry)
        try tracker.refreshEntries()
        try tracker.refreshReports()

        let midnight = startOfDay(daysAgo: 0)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id])
        XCTAssertEqual(tracker.projectTotalsForSelectedDay.first?.seconds, Int(end.timeIntervalSince(midnight)))

        try tracker.stepDay(by: -1)

        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id])
        XCTAssertEqual(tracker.projectTotalsForSelectedDay.first?.seconds, Int(midnight.timeIntervalSince(start)))
    }

    func testDeleteEntryOnAPastDayKeepsThatDaySelected() throws {
        try tracker.loadInitialState()
        let kept = try insert(daysAgo: 1, from: 9, to: 10)
        let removed = try insert(daysAgo: 1, from: 11, to: 12)
        try tracker.refreshEntries()
        try tracker.stepDay(by: -1)

        try tracker.deleteEntry(id: removed.id)

        XCTAssertFalse(tracker.isViewingToday)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [kept.id])
        XCTAssertEqual(tracker.projectTotalsForSelectedDay.first?.seconds, 3600)
    }

    func testEditingAPastEntryLeavesItOnItsOwnDay() throws {
        try tracker.loadInitialState()
        let entry = try insert(daysAgo: 1, from: 9, to: 10)
        try tracker.refreshEntries()
        try tracker.stepDay(by: -1)

        let editor = EntryEditor(days: clock.days)
        let fields = editor.withEnd(
            editor.fields(start: entry.start, end: entry.end),
            seconds: 11 * 3600
        )
        try tracker.updateEntry(id: entry.id, start: fields.start, end: fields.end, note: "fixed")

        XCTAssertFalse(tracker.isViewingToday)
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id])
        XCTAssertEqual(tracker.visibleEntries.first?.note, "fixed")
        XCTAssertEqual(tracker.projectTotalsForSelectedDay.first?.seconds, 2 * 3600)
        XCTAssertTrue(tracker.todaysEntries.isEmpty)
    }

    func testRunningEntryStartedYesterdayShowsOnBothDays() throws {
        try tracker.loadInitialState()
        let entry = TimeEntry(projectId: tracker.projects[0].id, start: time(daysAgo: 1, hour: 23))
        try timeEntryRepository.insertRunning(entry: entry)
        try tracker.refreshEntries()

        XCTAssertEqual(tracker.visibleEntries.map(\.id), [entry.id])

        try tracker.stepDay(by: -1)

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
        try tracker.refreshEntries()

        let midnight = startOfDay(daysAgo: 0)
        XCTAssertEqual(tracker.visibleDayTotalSeconds(), Int(end.timeIntervalSince(midnight)))

        try tracker.stepDay(by: -1)

        XCTAssertEqual(tracker.visibleDayTotalSeconds(), Int(midnight.timeIntervalSince(start)))
    }

    func testTodayTotalClipsAnEntrySpanningMidnightToToday() throws {
        try tracker.loadInitialState()
        let (_, end) = try insertSpanningMidnight()
        try tracker.refreshEntries()

        XCTAssertEqual(tracker.todayTotalSeconds(), Int(end.timeIntervalSince(startOfDay(daysAgo: 0))))
    }

    func testTodayTotalStaysOnTodayWhileTheHeaderTotalFollowsTheSelection() throws {
        try tracker.loadInitialState()
        try insert(daysAgo: 1, from: 9, to: 12)
        try insert(daysAgo: 0, from: 9, to: 10)
        try tracker.refreshEntries()

        XCTAssertEqual(tracker.todayTotalSeconds(), 3600)
        XCTAssertEqual(tracker.visibleDayTotalSeconds(), 3600)

        try tracker.stepDay(by: -1)

        XCTAssertEqual(tracker.todayTotalSeconds(), 3600)
        XCTAssertEqual(tracker.visibleDayTotalSeconds(), 3 * 3600)
    }

    // MARK: - Midnight Rollover

    func testRollOverMovesTheListOntoTheNewDay() throws {
        try tracker.loadInitialState()
        try insert(daysAgo: 1, from: 9, to: 10)
        clock.now = time(daysAgo: 1, hour: 23)
        try tracker.refreshEntries()
        XCTAssertEqual(tracker.visibleEntries.count, 1)

        clock.now = time(daysAgo: 0, hour: 0, minute: 30)
        XCTAssertTrue(try tracker.rollOverIfNeeded())

        XCTAssertTrue(tracker.isViewingToday)
        XCTAssertEqual(tracker.selectedDay(), startOfDay(daysAgo: 0))
        XCTAssertTrue(tracker.visibleEntries.isEmpty)
        XCTAssertTrue(tracker.todaysEntries.isEmpty)
    }

    func testRollOverHoldsABrowsedDayOnItsOwnDate() throws {
        clock.now = time(daysAgo: 1, hour: 23)
        try tracker.loadInitialState()
        let older = try insert(daysAgo: 2, from: 9, to: 10)
        try tracker.stepDay(by: -1)
        clock.now = time(daysAgo: 1, hour: 23)
        try tracker.refreshEntries()
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [older.id])

        clock.now = time(daysAgo: 0, hour: 0, minute: 30)
        XCTAssertTrue(try tracker.rollOverIfNeeded())

        XCTAssertEqual(tracker.dayOffset, -2)
        XCTAssertEqual(tracker.selectedDay(), startOfDay(daysAgo: 2))
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [older.id])
    }

    func testRollOverOutOfADayWithoutAMidnightHoldsABrowsedDayOnItsOwnDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santiago")!
        func santiago(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2024, month: 9, day: day, hour: hour, minute: minute))!
        }
        clock.calendar = calendar
        clock.now = santiago(8, 23)
        try tracker.loadInitialState()
        let older = TimeEntry(projectId: tracker.projects[0].id, start: santiago(7, 9), end: santiago(7, 10))
        try timeEntryRepository.insertRunning(entry: older)
        try tracker.stepDay(by: -1)
        clock.now = santiago(8, 23)
        clock.calendar = calendar
        try tracker.refreshEntries()
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [older.id])

        let now = santiago(9, 0, 30)
        clock.now = now
        XCTAssertTrue(try tracker.rollOverIfNeeded())

        XCTAssertEqual(tracker.dayOffset, -2)
        XCTAssertEqual(tracker.selectedDay(), santiago(7, 0))
        XCTAssertEqual(tracker.visibleEntries.map(\.id), [older.id])
    }

    func testRollOverAfterACalendarChangeHoldsABrowsedDayOnItsOwnDate() throws {
        func calendar(_ zone: String, _ system: Calendar.Identifier = .gregorian) -> Calendar {
            var calendar = Calendar(identifier: system)
            calendar.timeZone = TimeZone(identifier: zone)!
            return calendar
        }
        func date(_ month: Int, _ day: Int, _ hour: Int, in zone: String) -> Date {
            calendar(zone).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        let rollOvers: [(loaded: Calendar.Identifier, zone: String, system: Calendar.Identifier, month: Int, day: Int, hour: Int)] = [
            (.gregorian, "Europe/London", .gregorian, 10, 31, 10),
            (.gregorian, "Asia/Tokyo", .gregorian, 11, 1, 9),
            (.buddhist, "Europe/Berlin", .islamicCivil, 11, 1, 9),
        ]
        for (loaded, zone, system, month, day, hour) in rollOvers {
            clock.calendar = calendar("Europe/Berlin", loaded)
            clock.now = date(10, 31, 10, in: "Europe/Berlin")
            try tracker.loadInitialState()
            try tracker.stepDay(by: -1)
            clock.now = date(10, 31, 10, in: "Europe/Berlin")
            clock.calendar = calendar("Europe/Berlin", loaded)
            try tracker.refreshEntries()

            let moved = calendar(zone, system)
            let now = date(month, day, hour, in: zone)
            clock.now = now
            clock.calendar = moved
            XCTAssertTrue(try tracker.rollOverIfNeeded(), zone)

            XCTAssertEqual(tracker.selectedDay(), date(10, 30, 0, in: zone), zone)
        }
    }

    func testRollOverDoesNothingUntilTheDayActuallyChanges() throws {
        clock.now = time(daysAgo: 0, hour: 9)
        XCTAssertFalse(try tracker.rollOverIfNeeded())

        try tracker.loadInitialState()
        clock.now = time(daysAgo: 0, hour: 9)
        try tracker.refreshEntries()

        clock.now = time(daysAgo: 0, hour: 23)
        XCTAssertFalse(try tracker.rollOverIfNeeded())
    }
}
