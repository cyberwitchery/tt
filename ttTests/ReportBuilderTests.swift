import XCTest
@testable import tt

final class ReportBuilderTests: XCTestCase {
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
}
