import XCTest
@testable import tt

final class ReportBuilderTests: XCTestCase {
    // MARK: - Daily Totals

    func testDailyTotalsClipsToRange() {
        let calendar = Calendar(identifier: .gregorian)
        let rangeStart = calendar.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 10))!
        let rangeEnd = calendar.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 12))!
        let now = calendar.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 12))!

        let entry1 = TimeEntry(
            projectId: "a",
            start: calendar.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 9))!,
            end: calendar.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 11))!
        )
        let entry2 = TimeEntry(
            projectId: "a",
            start: calendar.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 11))!,
            end: calendar.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 13))!
        )
        let entry3 = TimeEntry(
            projectId: "b",
            start: calendar.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 8))!,
            end: calendar.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 9))!
        )
        let entry4 = TimeEntry(
            projectId: "b",
            start: calendar.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 10))!,
            end: calendar.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 12))!
        )

        let totals = ReportBuilder.dailyTotals(
            entries: [entry1, entry2, entry3, entry4],
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            now: now,
            projectNameForId: { $0 }
        )

        let totalsById = Dictionary(uniqueKeysWithValues: totals.map { ($0.id, $0.seconds) })
        XCTAssertEqual(totalsById["a"], 2 * 3600)
        XCTAssertEqual(totalsById["b"], 2 * 3600)
    }

    func testDailyTotalsEmptyEntries() {
        let rangeStart = Date.from(year: 2024, month: 1, day: 1)
        let rangeEnd = Date.from(year: 2024, month: 1, day: 2)

        let totals = ReportBuilder.dailyTotals(
            entries: [],
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            now: Date(),
            projectNameForId: { $0 }
        )

        XCTAssertTrue(totals.isEmpty)
    }

    func testDailyTotalsWithRunningEntry() {
        let rangeStart = Date.from(year: 2024, month: 1, day: 1, hour: 0)
        let rangeEnd = Date.from(year: 2024, month: 1, day: 2, hour: 0)
        let now = Date.from(year: 2024, month: 1, day: 1, hour: 10)

        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: nil
        )

        let totals = ReportBuilder.dailyTotals(
            entries: [entry],
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            now: now,
            projectNameForId: { _ in "test" }
        )

        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].seconds, 3600)
    }

    func testDailyTotalsSortsBySecondsDescending() {
        let rangeStart = Date.from(year: 2024, month: 1, day: 1, hour: 0)
        let rangeEnd = Date.from(year: 2024, month: 1, day: 2, hour: 0)

        let entries = [
            TimeEntry(
                projectId: "short",
                start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
                end: Date.from(year: 2024, month: 1, day: 1, hour: 10)
            ),
            TimeEntry(
                projectId: "long",
                start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
                end: Date.from(year: 2024, month: 1, day: 1, hour: 12)
            )
        ]

        let totals = ReportBuilder.dailyTotals(
            entries: entries,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            now: Date(),
            projectNameForId: { $0 }
        )

        XCTAssertEqual(totals[0].id, "long")
        XCTAssertEqual(totals[1].id, "short")
    }

    func testDailyTotalsAggregatesMultipleEntriesForSameProject() {
        let rangeStart = Date.from(year: 2024, month: 1, day: 1, hour: 0)
        let rangeEnd = Date.from(year: 2024, month: 1, day: 2, hour: 0)

        let entries = [
            TimeEntry(
                projectId: "p1",
                start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
                end: Date.from(year: 2024, month: 1, day: 1, hour: 10)
            ),
            TimeEntry(
                projectId: "p1",
                start: Date.from(year: 2024, month: 1, day: 1, hour: 14),
                end: Date.from(year: 2024, month: 1, day: 1, hour: 16)
            )
        ]

        let totals = ReportBuilder.dailyTotals(
            entries: entries,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            now: Date(),
            projectNameForId: { _ in "project" }
        )

        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].seconds, 3 * 3600)
    }

    func testDailyTotalsUsesProjectNameCallback() {
        let rangeStart = Date.from(year: 2024, month: 1, day: 1, hour: 0)
        let rangeEnd = Date.from(year: 2024, month: 1, day: 2, hour: 0)

        let entry = TimeEntry(
            projectId: "id123",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 10)
        )

        let totals = ReportBuilder.dailyTotals(
            entries: [entry],
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            now: Date(),
            projectNameForId: { _ in "custom name" }
        )

        XCTAssertEqual(totals[0].name, "custom name")
    }

    // MARK: - Weekly Totals

    func testWeeklyTotalsIncludeSevenDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let weekStart = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 0))!
        let now = calendar.date(from: DateComponents(year: 2024, month: 1, day: 7, hour: 12))!
        let entry = TimeEntry(
            projectId: "a",
            start: calendar.date(from: DateComponents(year: 2024, month: 1, day: 3, hour: 9))!,
            end: calendar.date(from: DateComponents(year: 2024, month: 1, day: 3, hour: 11))!
        )

        let totals = ReportBuilder.weeklyTotals(
            entries: [entry],
            weekStart: weekStart,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(totals.count, 7)
        let dayIndex = 2
        XCTAssertEqual(totals[dayIndex].seconds, 2 * 3600)
    }

    func testWeeklyTotalsEmptyEntries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let weekStart = Date.from(year: 2024, month: 1, day: 1)
        let now = Date.from(year: 2024, month: 1, day: 7)

        let totals = ReportBuilder.weeklyTotals(
            entries: [],
            weekStart: weekStart,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(totals.count, 7)
        for total in totals {
            XCTAssertEqual(total.seconds, 0)
        }
    }

    func testWeeklyTotalsWithRunningEntry() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let weekStart = Date.from(year: 2024, month: 1, day: 1)
        let now = Date.from(year: 2024, month: 1, day: 1, hour: 11)

        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: nil
        )

        let totals = ReportBuilder.weeklyTotals(
            entries: [entry],
            weekStart: weekStart,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(totals[0].seconds, 2 * 3600)
    }

    func testWeeklyTotalsEntrySpanningMultipleDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let weekStart = Date.from(year: 2024, month: 1, day: 1)
        let now = Date.from(year: 2024, month: 1, day: 7)

        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 22),
            end: Date.from(year: 2024, month: 1, day: 2, hour: 2)
        )

        let totals = ReportBuilder.weeklyTotals(
            entries: [entry],
            weekStart: weekStart,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(totals[0].seconds, 2 * 3600)
        XCTAssertEqual(totals[1].seconds, 2 * 3600)
    }

    func testWeeklyTotalsAggregatesMultipleEntriesPerDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let weekStart = Date.from(year: 2024, month: 1, day: 1)
        let now = Date.from(year: 2024, month: 1, day: 7)

        let entries = [
            TimeEntry(
                projectId: "p1",
                start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
                end: Date.from(year: 2024, month: 1, day: 1, hour: 10)
            ),
            TimeEntry(
                projectId: "p2",
                start: Date.from(year: 2024, month: 1, day: 1, hour: 14),
                end: Date.from(year: 2024, month: 1, day: 1, hour: 15)
            )
        ]

        let totals = ReportBuilder.weeklyTotals(
            entries: entries,
            weekStart: weekStart,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(totals[0].seconds, 2 * 3600)
    }
}
