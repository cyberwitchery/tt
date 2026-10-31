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

    // MARK: - fields(start:end:)

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

    // MARK: - unedited save on daylight-saving days

    private func gregorian(_ zone: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal
    }

    private func date(_ cal: Calendar, y: Int, mo: Int, d: Int, h: Int, m: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: m))!
    }

    /// `MainWindowView` opening the editor, pressing Enter in each of `enter`, then saving, with no text changed.
    private func saveUnedited(
        start: Date, end: Date?, enter: [EntryEditor.Field] = [], calendar cal: Calendar
    ) -> (start: Date, end: Date?) {
        var f = EntryEditor.fields(start: start, end: end, calendar: cal)
        for field in enter + [.start, .end, .duration] {
            f = EntryEditor.commit(EntryEditor.text(field, of: f), to: field, of: f)
        }
        return EntryEditor.resolve(f, editing: start, end: end, calendar: cal)
    }

    func testUneditedSaveKeepsEntryDatesExactly() {
        let rows: [(name: String, start: Date, end: Date?, enter: [EntryEditor.Field])] = [
            ("sub-second timer entry", date(h: 9, m: 15, s: 42) + 0.5, date(h: 10, m: 20, s: 13) + 0.7, []),
            ("28 s entry", date(h: 9, m: 15, s: 42), date(h: 9, m: 16, s: 10), []),
            ("26 h entry", date(d: 1, h: 9, m: 0), date(d: 2, h: 11, m: 0), []),
            ("exactly 24 h entry", date(d: 1, h: 9, m: 0), date(d: 2, h: 9, m: 0), []),
            ("running entry", date(h: 9, m: 15, s: 42), nil, []),
            ("Enter in every time field", date(h: 9, m: 15, s: 42), date(h: 10, m: 20, s: 13), [.start, .end, .duration]),
        ]
        for row in rows {
            let saved = saveUnedited(start: row.start, end: row.end, enter: row.enter, calendar: calendar)
            XCTAssertEqual(saved.start, row.start, row.name)
            XCTAssertEqual(saved.end, row.end, row.name)
        }
    }

    func testUneditedSaveKeepsEntryOnBerlinFallBackDay() {
        let cal = gregorian("Europe/Berlin")
        let start = date(cal, y: 2026, mo: 10, d: 25, h: 10, m: 0)
        let end = date(cal, y: 2026, mo: 10, d: 25, h: 11, m: 0)
        let saved = saveUnedited(start: start, end: end, calendar: cal)
        XCTAssertEqual(saved.start, start)
        XCTAssertEqual(saved.end, end)
    }

    func testUneditedSaveKeepsEntryOnBerlinSpringForwardDay() {
        let cal = gregorian("Europe/Berlin")
        let start = date(cal, y: 2026, mo: 3, d: 29, h: 10, m: 0)
        let end = date(cal, y: 2026, mo: 3, d: 29, h: 11, m: 0)
        let saved = saveUnedited(start: start, end: end, calendar: cal)
        XCTAssertEqual(saved.start, start)
        XCTAssertEqual(saved.end, end)
    }

    func testUneditedSaveKeepsEntryOnNewYorkSpringForwardDay() {
        let cal = gregorian("America/New_York")
        let start = date(cal, y: 2026, mo: 3, d: 8, h: 10, m: 0)
        let end = date(cal, y: 2026, mo: 3, d: 8, h: 11, m: 0)
        let saved = saveUnedited(start: start, end: end, calendar: cal)
        XCTAssertEqual(saved.start, start)
        XCTAssertEqual(saved.end, end)
    }

    func testUneditedSaveKeepsEntrySpanningBerlinFallBack() {
        let cal = gregorian("Europe/Berlin")
        let start = date(cal, y: 2026, mo: 10, d: 25, h: 1, m: 30)
        let end = date(cal, y: 2026, mo: 10, d: 25, h: 3, m: 30)
        XCTAssertEqual(end.timeIntervalSince(start), 3 * 3600)
        let saved = saveUnedited(start: start, end: end, calendar: cal)
        XCTAssertEqual(saved.start, start)
        XCTAssertEqual(saved.end, end)
    }

    func testResolveStartInSkippedHourLandsAtEndOfGap() {
        let cal = gregorian("Europe/Berlin")
        let base = date(cal, y: 2026, mo: 3, d: 29, h: 10, m: 0)
        let f = EntryEditor.Fields(startSeconds: 2 * 3600 + 30 * 60, endSeconds: 3 * 3600 + 30 * 60, durationSeconds: 3600)
        let (start, _) = EntryEditor.resolve(f, baseDate: base, calendar: cal)
        XCTAssertEqual(start, date(y: 2026, mo: 3, d: 29, h: 1, m: 0)) // 03:00 CEST
    }

    func testResolveStartInRepeatedHourTakesFirstOccurrence() {
        let cal = gregorian("Europe/Berlin")
        let base = date(cal, y: 2026, mo: 10, d: 25, h: 10, m: 0)
        let f = EntryEditor.Fields(startSeconds: 2 * 3600 + 30 * 60, endSeconds: 3 * 3600 + 30 * 60, durationSeconds: 3600)
        let (start, _) = EntryEditor.resolve(f, baseDate: base, calendar: cal)
        XCTAssertEqual(start, date(y: 2026, mo: 10, d: 25, h: 0, m: 30)) // 02:30 CEST
    }
}
