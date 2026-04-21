import XCTest
@testable import tt

final class EntryEditorTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(y: Int = 2025, mo: Int = 1, d: Int = 1, h: Int, m: Int, s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: m, second: s))!
    }

    // MARK: - fields(from:)

    func testFieldsFromStartAndEnd() {
        let start = date(h: 9, m: 30)
        let end = date(h: 11, m: 45)
        let f = EntryEditor.fields(start: start, end: end, calendar: calendar)
        XCTAssertEqual(f.startSeconds, 9 * 3600 + 30 * 60)
        XCTAssertEqual(f.endSeconds, 11 * 3600 + 45 * 60)
        XCTAssertEqual(f.durationSeconds, 2 * 3600 + 15 * 60)
    }

    func testFieldsFromRunningEntryHasZeroDuration() {
        let start = date(h: 14, m: 0)
        let f = EntryEditor.fields(start: start, end: nil, calendar: calendar)
        XCTAssertEqual(f.startSeconds, 14 * 3600)
        XCTAssertEqual(f.endSeconds, 14 * 3600)
        XCTAssertEqual(f.durationSeconds, 0)
    }

    func testFieldsFromCrossMidnightEntryCapsAtOneDay() {
        let start = date(d: 1, h: 23, m: 50)
        let end = date(d: 2, h: 0, m: 10)
        let f = EntryEditor.fields(start: start, end: end, calendar: calendar)
        XCTAssertEqual(f.startSeconds, 23 * 3600 + 50 * 60)
        XCTAssertEqual(f.endSeconds, 10 * 60)
        XCTAssertEqual(f.durationSeconds, 20 * 60)
    }

    // MARK: - withStart

    func testWithStartHoldsDurationAndShiftsEnd() {
        let base = EntryEditor.Fields(startSeconds: 9 * 3600, endSeconds: 10 * 3600, durationSeconds: 3600)
        let f = EntryEditor.withStart(base, seconds: 8 * 3600)
        XCTAssertEqual(f.startSeconds, 8 * 3600)
        XCTAssertEqual(f.durationSeconds, 3600)
        XCTAssertEqual(f.endSeconds, 9 * 3600)
    }

    func testWithStartWrapsEndAcrossMidnight() {
        let base = EntryEditor.Fields(startSeconds: 23 * 3600, endSeconds: 0, durationSeconds: 3600)
        let f = EntryEditor.withStart(base, seconds: 23 * 3600 + 30 * 60)
        XCTAssertEqual(f.startSeconds, 23 * 3600 + 30 * 60)
        XCTAssertEqual(f.durationSeconds, 3600)
        XCTAssertEqual(f.endSeconds, 30 * 60) // wrapped
    }

    // MARK: - withEnd

    func testWithEndHoldsStartAndRecomputesDuration() {
        let base = EntryEditor.Fields(startSeconds: 9 * 3600, endSeconds: 10 * 3600, durationSeconds: 3600)
        let f = EntryEditor.withEnd(base, seconds: 11 * 3600)
        XCTAssertEqual(f.startSeconds, 9 * 3600)
        XCTAssertEqual(f.endSeconds, 11 * 3600)
        XCTAssertEqual(f.durationSeconds, 2 * 3600)
    }

    func testWithEndBeforeStartAdds24HoursToDuration() {
        let base = EntryEditor.Fields(startSeconds: 23 * 3600, endSeconds: 23 * 3600, durationSeconds: 0)
        let f = EntryEditor.withEnd(base, seconds: 1 * 3600)
        XCTAssertEqual(f.startSeconds, 23 * 3600)
        XCTAssertEqual(f.endSeconds, 1 * 3600)
        XCTAssertEqual(f.durationSeconds, 2 * 3600) // 23:00 → 01:00 = 2h after +24h
    }

    // MARK: - withDuration

    func testWithDurationHoldsStartAndShiftsEnd() {
        let base = EntryEditor.Fields(startSeconds: 9 * 3600, endSeconds: 9 * 3600, durationSeconds: 0)
        let f = EntryEditor.withDuration(base, seconds: 90 * 60)
        XCTAssertEqual(f.startSeconds, 9 * 3600)
        XCTAssertEqual(f.durationSeconds, 90 * 60)
        XCTAssertEqual(f.endSeconds, 10 * 3600 + 30 * 60)
    }

    func testWithDurationClampsToOneDay() {
        let base = EntryEditor.Fields(startSeconds: 0, endSeconds: 0, durationSeconds: 0)
        let f = EntryEditor.withDuration(base, seconds: 90_000)
        XCTAssertEqual(f.durationSeconds, EntryEditor.secondsPerDay)
    }

    func testWithDurationClampsNegativeToZero() {
        let base = EntryEditor.Fields(startSeconds: 9 * 3600, endSeconds: 10 * 3600, durationSeconds: 3600)
        let f = EntryEditor.withDuration(base, seconds: -100)
        XCTAssertEqual(f.durationSeconds, 0)
        XCTAssertEqual(f.endSeconds, 9 * 3600)
    }

    // MARK: - resolve

    func testResolveProducesDatesOnSameDay() {
        let baseDate = date(h: 14, m: 0)
        let f = EntryEditor.Fields(startSeconds: 9 * 3600, endSeconds: 10 * 3600, durationSeconds: 3600)
        let (start, end) = EntryEditor.resolve(f, baseDate: baseDate, calendar: calendar)
        XCTAssertEqual(start, date(h: 9, m: 0))
        XCTAssertEqual(end, date(h: 10, m: 0))
    }

    func testResolveCrossesMidnightWhenDurationSpansIt() {
        let baseDate = date(h: 23, m: 0)
        let f = EntryEditor.Fields(startSeconds: 23 * 3600, endSeconds: 1 * 3600, durationSeconds: 2 * 3600)
        let (start, end) = EntryEditor.resolve(f, baseDate: baseDate, calendar: calendar)
        XCTAssertEqual(start, date(d: 1, h: 23, m: 0))
        XCTAssertEqual(end, date(d: 2, h: 1, m: 0))
    }
}
