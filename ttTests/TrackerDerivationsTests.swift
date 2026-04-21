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
        // Close that entry manually at `end`.
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

        // Clock skew: now earlier than last end.
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
        // Currently running entry should not be reflected in completed totals.
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
}
