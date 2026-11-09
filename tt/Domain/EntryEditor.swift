import Foundation

/// Bound wall-clock fields for the inline entry editor. Durations are elapsed seconds.
struct EntryEditor {
    struct Fields: Equatable {
        var start: Date
        var end: Date?

        var durationSeconds: Int { TimeMath.durationSeconds(start: start, end: end ?? start) }
    }

    let days: DayCalendar

    func fields(start: Date, end: Date?) -> Fields {
        Fields(start: start, end: end)
    }

    /// edit `start`: hold duration, recompute end.
    func withStart(_ fields: Fields, seconds: Int) -> Fields {
        let start = days.date(at: seconds, on: days.day(containing: fields.start))
        let end = fields.end.map { start.addingTimeInterval(max(0, $0.timeIntervalSince(fields.start))) }
        return Fields(start: start, end: end)
    }

    /// edit `end`: resolve its wall time on the start day, or the next day if earlier.
    func withEnd(_ fields: Fields, seconds: Int) -> Fields {
        Fields(start: fields.start, end: days.end(at: seconds, after: fields.start))
    }

    /// edit `duration`: hold start, capped at the same wall time on the next calendar day.
    func withDuration(_ fields: Fields, seconds: Int) -> Fields {
        let limit = days.nextDay(atTimeOf: fields.start).timeIntervalSince(fields.start)
        let duration = min(max(0, TimeInterval(seconds)), limit)
        return Fields(start: fields.start, end: fields.start.addingTimeInterval(duration))
    }

    enum Field { case start, end, duration }

    /// the text the editor shows for `field`: HH:MM for start and end, HH:MM:SS for duration.
    func text(_ field: Field, of fields: Fields) -> String {
        switch field {
        case .start: return Self.formatHHMM(days.timeOfDaySeconds(fields.start))
        case .end: return Self.formatHHMM(days.timeOfDaySeconds(fields.end ?? fields.start))
        case .duration: return Self.formatHHMMSS(fields.durationSeconds)
        }
    }

    /// apply `text` as an edit of `field`; text that `fields` already shows, or that does not parse, changes nothing.
    func commit(_ text: String, to field: Field, of fields: Fields) -> Fields {
        guard text != self.text(field, of: fields) else { return fields }
        switch field {
        case .start: return Self.parseHHMM(text).map { withStart(fields, seconds: $0) } ?? fields
        case .end: return Self.parseHHMM(text).map { withEnd(fields, seconds: $0) } ?? fields
        case .duration: return Self.parseHHMMSS(text).map { withDuration(fields, seconds: $0) } ?? fields
        }
    }

    /// commit each text that differs from what `fields` shows, in the order start, end, duration.
    func commit(start: String, end: String, duration: String, to fields: Fields) -> Fields {
        var edited = fields
        for (field, text) in [(Field.start, start), (.end, end), (.duration, duration)] where text != self.text(field, of: fields) {
            edited = commit(text, to: field, of: edited)
        }
        return edited
    }

    private static func parseHHMM(_ text: String) -> Int? {
        let parts = text.split(separator: ":").map(String.init)
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              h >= 0, h < 24, m >= 0, m < 60 else { return nil }
        return h * 3600 + m * 60
    }

    private static func parseHHMMSS(_ text: String) -> Int? {
        let parts = text.split(separator: ":").map(String.init)
        if parts.count == 3,
           let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]),
           h >= 0, m >= 0, m < 60, s >= 0, s < 60 {
            return h * 3600 + m * 60 + s
        }
        if parts.count == 2,
           let h = Int(parts[0]), let m = Int(parts[1]),
           h >= 0, m >= 0, m < 60 {
            return h * 3600 + m * 60
        }
        return nil
    }

    private static func formatHHMM(_ seconds: Int) -> String {
        let h = (seconds / 3600) % 24
        let m = (seconds % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }

    private static func formatHHMMSS(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}


struct EntryEditSession {
    struct Update: Equatable {
        let id: String
        let start: Date
        let end: Date?
        let note: String
        let projectId: String
    }

    private let editor: EntryEditor
    private var entry: TimeEntry?
    private var fields = EntryEditor.Fields(start: .distantPast, end: nil)
    var projectId: String?
    var note = ""
    var startText = ""
    var endText = ""
    var durationText = ""
    var projectPickerOpen = false
    var entryId: String? { entry?.id }

    var endDayOffset: Int {
        guard let update = update(runningEntryId: nil), let end = update.end else { return 0 }
        return editor.days.daysBetween(editor.days.day(containing: update.start), and: editor.days.day(containing: end))
    }

    init(days: DayCalendar) { editor = EntryEditor(days: days) }

    mutating func begin(_ entry: TimeEntry) {
        clear()
        self.entry = entry
        projectId = entry.projectId
        note = entry.note ?? ""
        fields = editor.fields(start: entry.start, end: entry.end)
        syncTexts()
    }

    mutating func clear() {
        self = EntryEditSession(days: editor.days)
    }

    mutating func commit(_ field: EntryEditor.Field) {
        let text: String
        switch field {
        case .start: text = startText
        case .end: text = endText
        case .duration: text = durationText
        }
        fields = editor.commit(text, to: field, of: fields)
        syncTexts()
    }

    func update(runningEntryId: String?) -> Update? {
        guard let entry else { return nil }
        let edited = editor.commit(start: startText, end: endText, duration: durationText, to: fields)
        return Update(id: entry.id, start: edited.start, end: entry.id == runningEntryId ? nil : edited.end,
                      note: note, projectId: projectId ?? entry.projectId)
    }

    private mutating func syncTexts() {
        startText = editor.text(.start, of: fields)
        endText = editor.text(.end, of: fields)
        durationText = editor.text(.duration, of: fields)
    }
}
