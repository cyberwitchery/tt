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

    private func makeEditor(calendar: Calendar) -> EntryEditor {
        EntryEditor(days: DayCalendar(calendar: { calendar }))
    }

    private var editor: EntryEditor { makeEditor(calendar: calendar) }

    // MARK: - fields(start:end:)

    func testFieldsFromStartAndEnd() {
        let start = date(h: 9, m: 30)
        let end = date(h: 11, m: 45)
        let f = editor.fields(start: start, end: end)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.start), 9 * 3600 + 30 * 60)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.end ?? f.start), 11 * 3600 + 45 * 60)
        XCTAssertEqual(f.durationSeconds, 2 * 3600 + 15 * 60)
    }

    func testFieldsFromRunningEntryHasZeroDuration() {
        let start = date(h: 14, m: 0)
        let f = editor.fields(start: start, end: nil)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.start), 14 * 3600)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.end ?? f.start), 14 * 3600)
        XCTAssertEqual(f.durationSeconds, 0)
    }

    func testFieldsFromCrossMidnightEntry() {
        let start = date(d: 1, h: 23, m: 50)
        let end = date(d: 2, h: 0, m: 10)
        let f = editor.fields(start: start, end: end)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.start), 23 * 3600 + 50 * 60)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.end ?? f.start), 10 * 60)
        XCTAssertEqual(f.durationSeconds, 20 * 60)
    }

    // MARK: - withStart

    func testWithStartHoldsDurationAndShiftsEnd() {
        let base = editor.fields(start: date(h: 9, m: 0), end: date(h: 10, m: 0))
        let f = editor.withStart(base, seconds: 8 * 3600)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.start), 8 * 3600)
        XCTAssertEqual(f.durationSeconds, 3600)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.end ?? f.start), 9 * 3600)
    }

    func testWithStartWrapsEndAcrossMidnight() {
        let base = editor.fields(start: date(h: 23, m: 0), end: date(d: 2, h: 0, m: 0))
        let f = editor.withStart(base, seconds: 23 * 3600 + 30 * 60)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.start), 23 * 3600 + 30 * 60)
        XCTAssertEqual(f.durationSeconds, 3600)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.end ?? f.start), 30 * 60) // wrapped
    }

    // MARK: - withEnd

    func testWithEndHoldsStartAndRecomputesDuration() {
        let base = editor.fields(start: date(h: 9, m: 0), end: date(h: 10, m: 0))
        let f = editor.withEnd(base, seconds: 11 * 3600)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.start), 9 * 3600)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.end ?? f.start), 11 * 3600)
        XCTAssertEqual(f.durationSeconds, 2 * 3600)
    }

    func testWithEndBeforeStartUsesTheNextDay() {
        let base = editor.fields(start: date(h: 23, m: 0), end: date(h: 23, m: 0))
        let f = editor.withEnd(base, seconds: 1 * 3600)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.start), 23 * 3600)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.end ?? f.start), 1 * 3600)
        XCTAssertEqual(f.durationSeconds, 2 * 3600)
        XCTAssertEqual(f.end, date(d: 2, h: 1, m: 0))
    }

    // MARK: - withDuration

    func testWithDurationHoldsStartAndShiftsEnd() {
        let base = editor.fields(start: date(h: 9, m: 0), end: date(h: 9, m: 0))
        let f = editor.withDuration(base, seconds: 90 * 60)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.start), 9 * 3600)
        XCTAssertEqual(f.durationSeconds, 90 * 60)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.end ?? f.start), 10 * 3600 + 30 * 60)
    }

    func testWithDurationClampsToOneDay() {
        let base = editor.fields(start: date(h: 0, m: 0), end: date(h: 0, m: 0))
        let f = editor.withDuration(base, seconds: 90_000)
        XCTAssertEqual(f.durationSeconds, 24 * 3600)
    }

    func testWithDurationClampsNegativeToZero() {
        let base = editor.fields(start: date(h: 9, m: 0), end: date(h: 10, m: 0))
        let f = editor.withDuration(base, seconds: -100)
        XCTAssertEqual(f.durationSeconds, 0)
        XCTAssertEqual(editor.days.timeOfDaySeconds(f.end ?? f.start), 9 * 3600)
    }

    // MARK: - dates

    func testFieldsRetainDatesOnSameDay() {
        let f = editor.fields(start: date(h: 9, m: 0), end: date(h: 10, m: 0))
        XCTAssertEqual(f.start, date(h: 9, m: 0))
        XCTAssertEqual(f.end, date(h: 10, m: 0))
    }

    func testDurationEditCrossesMidnight() {
        let f = editor.withDuration(editor.fields(start: date(h: 23, m: 0), end: nil), seconds: 2 * 3600)
        XCTAssertEqual(f.start, date(d: 1, h: 23, m: 0))
        XCTAssertEqual(f.end, date(d: 2, h: 1, m: 0))
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

    /// Save applies typed fields even if Enter was not pressed.
    private func save(
        _ fields: EntryEditor.Fields, typed: [EntryEditor.Field: String] = [:], calendar cal: Calendar
    ) -> (start: Date, end: Date?) {
        let editor = makeEditor(calendar: cal)
        func shown(_ field: EntryEditor.Field) -> String { typed[field] ?? editor.text(field, of: fields) }
        let f = editor.commit(start: shown(.start), end: shown(.end), duration: shown(.duration), to: fields)
        return (f.start, f.end)
    }

    /// `MainWindowView` opening the editor, pressing Enter in each of `enter`, then saving, with no text changed.
    private func saveUnedited(
        start: Date, end: Date?, enter: [EntryEditor.Field] = [], calendar cal: Calendar
    ) -> (start: Date, end: Date?) {
        let editor = makeEditor(calendar: cal)
        var f = editor.fields(start: start, end: end)
        for field in enter {
            f = editor.commit(editor.text(field, of: f), to: field, of: f)
        }
        return save(f, calendar: cal)
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

    func testEnteringANewEndKeepsTheStartToTheSecond() {
        let start = date(h: 9, m: 15, s: 42)
        let end = date(h: 10, m: 20, s: 13)
        let edited = editor.commit("11:00", to: .end, of: editor.fields(start: start, end: end))
        let saved = save(edited, calendar: calendar)
        XCTAssertEqual(saved.start, start)
        XCTAssertEqual(saved.end, date(h: 11, m: 0))
    }

    func testSaveAppliesTextsTypedWithoutEnter() {
        let start = date(h: 10, m: 0)
        let end = date(h: 11, m: 0)
        let rows: [(name: String, entered: [(EntryEditor.Field, String)], typed: [EntryEditor.Field: String], start: Date, end: Date)] = [
            ("start", [], [.start: "09:30"], date(h: 9, m: 30), date(h: 10, m: 30)),
            ("end", [], [.end: "12:00"], start, date(h: 12, m: 0)),
            ("duration", [], [.duration: "02:00:00"], start, date(h: 12, m: 0)),
            ("start and end", [], [.start: "09:00", .end: "12:00"], date(h: 9, m: 0), date(h: 12, m: 0)),
            ("end and duration", [], [.end: "12:00", .duration: "00:30:00"], start, date(h: 10, m: 30)),
            ("unparseable end", [], [.start: "09:00", .end: "1200", .duration: "02:00:00"], date(h: 9, m: 0), date(h: 11, m: 0)),
            ("end after an entered start", [(.start, "09:30")], [.end: "12:00"], date(h: 9, m: 30), date(h: 12, m: 0)),
            ("nothing", [], [:], start, end),
        ]
        for row in rows {
            var f = editor.fields(start: start, end: end)
            for (field, text) in row.entered {
                f = editor.commit(text, to: field, of: f)
            }
            let saved = save(f, typed: row.typed, calendar: calendar)
            XCTAssertEqual(saved.start, row.start, row.name)
            XCTAssertEqual(saved.end, row.end, row.name)
        }
    }

    func testResolveStartInSkippedHourLandsAtEndOfGap() {
        let cal = gregorian("Europe/Berlin")
        let base = date(cal, y: 2026, mo: 3, d: 29, h: 10, m: 0)
        let editor = makeEditor(calendar: cal)
        let f = editor.withStart(editor.fields(start: base, end: nil), seconds: 2 * 3600 + 30 * 60)
        XCTAssertEqual(f.start, date(y: 2026, mo: 3, d: 29, h: 1, m: 0)) // 03:00 CEST
    }

    func testEditingEndAcrossDaylightSavingKeepsTheEnteredWallTime() {
        let cal = gregorian("Europe/Berlin")
        for (month, day, elapsedHours) in [(3, 29, 1), (10, 25, 3)] {
            let start = date(cal, y: 2026, mo: month, d: day, h: 1, m: 30)
            let originalEnd = date(cal, y: 2026, mo: month, d: day, h: 1, m: 45)
            let editor = makeEditor(calendar: cal)
            let fields = editor.fields(start: start, end: originalEnd)

            let saved = save(fields, typed: [.end: "03:30"], calendar: cal)

            XCTAssertEqual(saved.start, start)
            XCTAssertEqual(saved.end, date(cal, y: 2026, mo: month, d: day, h: 3, m: 30))
            XCTAssertEqual(saved.end?.timeIntervalSince(start), TimeInterval(elapsedHours * 3600))
        }
    }

    func testDurationEditUsesElapsedTimeAcrossDaylightSaving() {
        let cal = gregorian("Europe/Berlin")
        let editor = makeEditor(calendar: cal)
        for (month, day, endHour) in [(3, 29, 4), (10, 25, 2)] {
            let start = date(cal, y: 2026, mo: month, d: day, h: 1, m: 30)
            let fields = editor.commit("02:00:00", to: .duration, of: editor.fields(start: start, end: nil))

            XCTAssertEqual(fields.end?.timeIntervalSince(start), 2 * 3600)
            XCTAssertEqual(editor.text(.end, of: fields), String(format: "%02d:30", endHour))
            XCTAssertEqual(editor.text(.duration, of: fields), "02:00:00")
        }
    }

    func testDurationLimitUsesTheLengthOfTheCalendarDay() {
        let cal = gregorian("Europe/Berlin")
        let editor = makeEditor(calendar: cal)
        for (month, day, hours) in [(3, 29, 23), (10, 25, 25)] {
            let start = date(cal, y: 2026, mo: month, d: day, h: 0, m: 0) + 0.5
            let fields = editor.withDuration(editor.fields(start: start, end: nil), seconds: 30 * 3600)

            XCTAssertEqual(fields.durationSeconds, hours * 3600)
            XCTAssertEqual(fields.end, date(cal, y: 2026, mo: month, d: day + 1, h: 0, m: 0) + 0.5)
        }
    }

    func testResolveStartInRepeatedHourTakesFirstOccurrence() {
        let cal = gregorian("Europe/Berlin")
        let base = date(cal, y: 2026, mo: 10, d: 25, h: 10, m: 0)
        let editor = makeEditor(calendar: cal)
        let f = editor.withStart(editor.fields(start: base, end: nil), seconds: 2 * 3600 + 30 * 60)
        XCTAssertEqual(f.start, date(y: 2026, mo: 10, d: 25, h: 0, m: 30)) // 02:30 CEST
    }
}

final class EntryEditSessionTests: XCTestCase {
    func testSaveArgumentsKeepAnEndWrittenAfterTheEditorOpened() throws {
        let start = Date.from(year: 2026, month: 1, day: 1, hour: 9)
        let stoppedEnd = start.addingTimeInterval(3600)
        var session = session()
        session.begin(TimeEntry(projectId: "p", start: start))
        session.note = "updated"
        XCTAssertEqual(session.update(runningEntryId: nil, currentEnd: stoppedEnd)?.end, stoppedEnd)
        session.endText = "11:00"
        XCTAssertEqual(session.update(runningEntryId: nil, currentEnd: stoppedEnd)?.end, start.addingTimeInterval(7200))
    }

    func testSavingAnOpenEditorAfterStopDoesNotReopenTheTimer() throws {
        let database = try TestDatabase.makeInMemory()
        let clock = TestClock()
        clock.now = Date.from(year: 2026, month: 1, day: 1, hour: 9)
        let entries = TimeEntryRepository(dbQueue: database)
        let tracker = TimeTracker(projectRepository: ProjectRepository(dbQueue: database), timeEntryRepository: entries, days: clock.days)
        try tracker.loadInitialState()
        try tracker.startTimer()
        let running = try XCTUnwrap(tracker.runningEntry)
        var session = EntryEditSession(days: clock.days)
        session.begin(running)

        clock.now = clock.now.addingTimeInterval(3600)
        try tracker.stopTimer()
        let stopped = try XCTUnwrap(entries.get(id: running.id))
        session.note = "saved after stopping"
        let update = try XCTUnwrap(session.update(runningEntryId: tracker.runningEntry?.id))
        try tracker.updateEntry(id: update.id, start: update.start, end: update.end, note: update.note, projectId: update.projectId)

        XCTAssertNil(tracker.runningEntry)
        XCTAssertEqual(try entries.get(id: running.id)?.end, stopped.end)
        XCTAssertEqual(try entries.get(id: running.id)?.note, "saved after stopping")
    }

    private func session() -> EntryEditSession {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return EntryEditSession(days: DayCalendar(calendar: { calendar }))
    }

    func testEndDayOffsetDistinguishesAFullDayFromZeroDuration() {
        let start = Date.from(year: 2026, month: 1, day: 1, hour: 9)
        var session = session()
        XCTAssertEqual(session.endDayOffset, 0)
        session.begin(TimeEntry(projectId: "p", start: start, end: start + 86400))
        XCTAssertEqual(session.startText, session.endText)
        XCTAssertEqual(session.endDayOffset, 1)
        session.durationText = "00:00:00"
        XCTAssertEqual(session.endDayOffset, 0)
    }

    func testSaveAppliesAllTypedFieldsAndProjectFallback() throws {
        let start = Date.from(year: 2026, month: 1, day: 1, hour: 9)
        let entry = TimeEntry(projectId: "original", start: start, end: start + 3600)
        var session = session()
        session.begin(entry)
        session.startText = "08:00"
        session.endText = "11:00"
        session.durationText = "02:00:00"
        session.projectId = nil
        session.note = "updated"
        let update = try XCTUnwrap(session.update(runningEntryId: nil))
        XCTAssertEqual(update.id, entry.id)
        XCTAssertEqual(update.start, start - 3600)
        XCTAssertEqual(update.end, start + 3600)
        XCTAssertEqual(update.projectId, "original")
        XCTAssertEqual(update.note, "updated")
        session.projectId = "new"
        XCTAssertEqual(session.update(runningEntryId: nil)?.projectId, "new")
    }

    func testRunningEntryStaysRunningAfterEndAndDurationEdits() {
        let entry = TimeEntry(projectId: "p", start: Date.from(year: 2026, month: 1, day: 1, hour: 9))
        var session = session()
        session.begin(entry)
        session.endText = "12:00"
        session.durationText = "02:00:00"
        XCTAssertNil(session.update(runningEntryId: entry.id)?.end)
        XCTAssertNotNil(session.update(runningEntryId: nil)?.end)
    }

    func testCommitSynchronizesTextsAndClearResetsEverything() {
        let start = Date.from(year: 2026, month: 1, day: 1, hour: 9)
        let entry = TimeEntry(projectId: "p", start: start, end: start + 3600, note: "old")
        var session = session()
        session.begin(entry)
        session.startText = "08:00"
        session.commit(.start)
        XCTAssertEqual(session.endText, "09:00")
        XCTAssertEqual(session.durationText, "01:00:00")
        session.projectPickerOpen = true
        session.clear()
        XCTAssertNil(session.entryId)
        XCTAssertNil(session.projectId)
        XCTAssertEqual(session.note, "")
        XCTAssertEqual(session.startText, "")
        XCTAssertEqual(session.endText, "")
        XCTAssertEqual(session.durationText, "")
        XCTAssertFalse(session.projectPickerOpen)
        XCTAssertNil(session.update(runningEntryId: nil))
        session.begin(TimeEntry(projectId: "second", start: start))
        XCTAssertEqual(session.note, "")
        XCTAssertEqual(session.durationText, "00:00:00")
        XCTAssertEqual(session.projectId, "second")
    }
}
