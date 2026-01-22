import XCTest
import GRDB
@testable import tt

final class TimeEntryRepositoryTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    var repository: TimeEntryRepository!

    override func setUp() {
        super.setUp()
        dbQueue = try! TestDatabase.makeInMemory()
        repository = TimeEntryRepository(dbQueue: dbQueue)
    }

    override func tearDown() {
        dbQueue = nil
        repository = nil
        super.tearDown()
    }

    // MARK: - Insert and Fetch

    func testInsertRunningAndFetchRunning() throws {
        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9)
        )

        try repository.insertRunning(entry: entry)

        let running = try repository.fetchRunning()
        XCTAssertNotNil(running)
        XCTAssertEqual(running?.id, entry.id)
        XCTAssertNil(running?.end)
    }

    func testFetchRunningReturnsNilWhenNoRunning() throws {
        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 10)
        )

        try repository.insertRunning(entry: entry)

        let running = try repository.fetchRunning()
        XCTAssertNil(running)
    }

    // MARK: - Stop Running

    func testStopRunning() throws {
        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9)
        )

        try repository.insertRunning(entry: entry)

        let endTime = Date.from(year: 2024, month: 1, day: 1, hour: 10)
        let stopped = try repository.stopRunning(entry: entry, end: endTime)

        XCTAssertEqual(stopped.end, endTime)

        let running = try repository.fetchRunning()
        XCTAssertNil(running)
    }

    // MARK: - Update

    func testUpdate() throws {
        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 10)
        )

        try repository.insertRunning(entry: entry)

        var updated = entry
        updated.note = "updated note"
        updated.start = Date.from(year: 2024, month: 1, day: 1, hour: 8)

        try repository.update(updated)

        let fetched = try dbQueue.read { db in
            try TimeEntry.fetchOne(db, key: entry.id)
        }

        XCTAssertEqual(fetched?.note, "updated note")
        XCTAssertEqual(fetched?.start, Date.from(year: 2024, month: 1, day: 1, hour: 8))
    }

    // MARK: - Delete

    func testDelete() throws {
        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9)
        )

        try repository.insertRunning(entry: entry)
        try repository.delete(id: entry.id)

        let count = try dbQueue.read { db in
            try TimeEntry.fetchCount(db)
        }

        XCTAssertEqual(count, 0)
    }

    // MARK: - Fetch Entries in Range

    func testFetchEntriesInRange() throws {
        let entry1 = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 10)
        )
        let entry2 = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 2, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 2, hour: 10)
        )
        let entry3 = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 3, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 3, hour: 10)
        )

        try repository.insertRunning(entry: entry1)
        try repository.insertRunning(entry: entry2)
        try repository.insertRunning(entry: entry3)

        let rangeStart = Date.from(year: 2024, month: 1, day: 2)
        let rangeEnd = Date.from(year: 2024, month: 1, day: 3)

        let fetched = try repository.fetchEntries(in: rangeStart..<rangeEnd)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, entry2.id)
    }

    func testFetchEntriesIncludesOverlapping() throws {
        // Entry that starts before range but ends within
        let overlapsStart = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 8),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 11)
        )
        // Entry that starts within range but ends after
        let overlapsEnd = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 14),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 18)
        )
        // Entry fully within range
        let within = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 11),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 13)
        )
        // Entry fully outside range
        let outside = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 2, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 2, hour: 10)
        )

        try repository.insertRunning(entry: overlapsStart)
        try repository.insertRunning(entry: overlapsEnd)
        try repository.insertRunning(entry: within)
        try repository.insertRunning(entry: outside)

        let rangeStart = Date.from(year: 2024, month: 1, day: 1, hour: 10)
        let rangeEnd = Date.from(year: 2024, month: 1, day: 1, hour: 15)

        let fetched = try repository.fetchEntries(in: rangeStart..<rangeEnd)

        XCTAssertEqual(fetched.count, 3)
        let ids = Set(fetched.map { $0.id })
        XCTAssertTrue(ids.contains(overlapsStart.id))
        XCTAssertTrue(ids.contains(overlapsEnd.id))
        XCTAssertTrue(ids.contains(within.id))
        XCTAssertFalse(ids.contains(outside.id))
    }

    func testFetchEntriesIncludesRunningEntry() throws {
        let running = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: nil
        )

        try repository.insertRunning(entry: running)

        let rangeStart = Date.from(year: 2024, month: 1, day: 1)
        let rangeEnd = Date.from(year: 2024, month: 1, day: 2)

        let fetched = try repository.fetchEntries(in: rangeStart..<rangeEnd)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, running.id)
    }

    // MARK: - Resolve Multiple Running

    func testResolveMultipleRunningEntries() throws {
        let first = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9)
        )
        let second = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 10)
        )
        let third = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 11)
        )

        try repository.insertRunning(entry: first)
        try repository.insertRunning(entry: second)
        try repository.insertRunning(entry: third)

        try repository.resolveMultipleRunningEntries()

        let running = try repository.fetchRunning()
        XCTAssertNotNil(running)
        XCTAssertEqual(running?.id, third.id) // Most recent stays running

        let all = try dbQueue.read { db in
            try TimeEntry.fetchAll(db)
        }

        let closed = all.filter { $0.end != nil }
        XCTAssertEqual(closed.count, 2)

        // Verify the older entries were closed at the start of the newest running
        for entry in closed {
            XCTAssertEqual(entry.end, third.start)
        }
    }

    func testResolveMultipleRunningDoesNothingWithSingleRunning() throws {
        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9)
        )

        try repository.insertRunning(entry: entry)
        try repository.resolveMultipleRunningEntries()

        let running = try repository.fetchRunning()
        XCTAssertNotNil(running)
        XCTAssertNil(running?.end)
    }

    func testResolveMultipleRunningDoesNothingWithNoRunning() throws {
        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 10)
        )

        try repository.insertRunning(entry: entry)
        try repository.resolveMultipleRunningEntries()

        let all = try dbQueue.read { db in
            try TimeEntry.fetchAll(db)
        }
        XCTAssertEqual(all.count, 1)
        XCTAssertNotNil(all[0].end)
    }

    // MARK: - Fetch Running Returns Most Recent

    func testFetchRunningReturnsMostRecentWhenMultiple() throws {
        let older = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9)
        )
        let newer = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 10)
        )

        try repository.insertRunning(entry: older)
        try repository.insertRunning(entry: newer)

        let running = try repository.fetchRunning()
        XCTAssertEqual(running?.id, newer.id)
    }

    // MARK: - Fetch Entries Ordering

    func testFetchEntriesOrdersByStartDescending() throws {
        let early = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 10)
        )
        let late = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 14),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 15)
        )

        try repository.insertRunning(entry: early)
        try repository.insertRunning(entry: late)

        let rangeStart = Date.from(year: 2024, month: 1, day: 1)
        let rangeEnd = Date.from(year: 2024, month: 1, day: 2)

        let fetched = try repository.fetchEntries(in: rangeStart..<rangeEnd)

        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched[0].id, late.id)
        XCTAssertEqual(fetched[1].id, early.id)
    }

    // MARK: - Delete Non-Existent

    func testDeleteNonExistentDoesNotThrow() throws {
        XCTAssertNoThrow(try repository.delete(id: "non-existent-id"))
    }

    // MARK: - Empty Database

    func testFetchRunningOnEmptyDatabase() throws {
        let running = try repository.fetchRunning()
        XCTAssertNil(running)
    }

    func testFetchEntriesOnEmptyDatabase() throws {
        let rangeStart = Date.from(year: 2024, month: 1, day: 1)
        let rangeEnd = Date.from(year: 2024, month: 1, day: 2)

        let fetched = try repository.fetchEntries(in: rangeStart..<rangeEnd)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testResolveMultipleRunningOnEmptyDatabase() throws {
        XCTAssertNoThrow(try repository.resolveMultipleRunningEntries())
    }
}
