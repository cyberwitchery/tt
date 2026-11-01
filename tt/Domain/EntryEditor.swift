import Foundation

/// pure HH:MM / HH:MM:SS bound-field math for the inline entry editor.
///
/// fields are `startSeconds`, `endSeconds` (both 0..86399, expected to be
/// minute-aligned when edited via the UI) and `durationSeconds` (0..86400).
/// cross-midnight is modeled by adding 24h to the duration when `end < start`;
/// that's the only cross-midnight case the editor supports.
enum EntryEditor {
    struct Fields: Equatable {
        var startSeconds: Int
        var endSeconds: Int
        var durationSeconds: Int
    }

    static let secondsPerDay = 86_400

    /// build initial fields from an entry's start and optional end, using the
    /// calendar to extract the time-of-day portion.
    static func fields(start: Date, end: Date?, calendar: Calendar = .current) -> Fields {
        let startSec = timeOfDaySeconds(start, calendar: calendar)
        guard let end else {
            return Fields(startSeconds: startSec, endSeconds: startSec, durationSeconds: 0)
        }
        let endSec = timeOfDaySeconds(end, calendar: calendar)
        let raw = Int(end.timeIntervalSince(start).rounded(.down))
        let dur = max(0, min(secondsPerDay, raw))
        return Fields(startSeconds: startSec, endSeconds: endSec, durationSeconds: dur)
    }

    /// edit `start`: hold duration, recompute end.
    static func withStart(_ fields: Fields, seconds: Int) -> Fields {
        var f = fields
        f.startSeconds = clampTimeOfDay(seconds)
        f.endSeconds = (f.startSeconds + f.durationSeconds) % secondsPerDay
        return f
    }

    /// edit `end`: hold start, recompute duration (+24h if crossed midnight).
    static func withEnd(_ fields: Fields, seconds: Int) -> Fields {
        var f = fields
        f.endSeconds = clampTimeOfDay(seconds)
        var dur = f.endSeconds - f.startSeconds
        if dur < 0 { dur += secondsPerDay }
        f.durationSeconds = dur
        return f
    }

    /// edit `duration`: hold start, recompute end (wrapping modulo 24h).
    static func withDuration(_ fields: Fields, seconds: Int) -> Fields {
        var f = fields
        f.durationSeconds = max(0, min(secondsPerDay, seconds))
        f.endSeconds = (f.startSeconds + f.durationSeconds) % secondsPerDay
        return f
    }

    /// resolve fields back to `(start, end)` Date values anchored to `baseDate`'s day.
    /// the returned `end` may fall on the next calendar day if the duration crosses midnight.
    /// a start inside a skipped daylight-saving hour resolves to the end of the gap; a repeated one to its first occurrence.
    static func resolve(_ fields: Fields, baseDate: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let dayStart = calendar.startOfDay(for: baseDate)
        let start = calendar.date(
            bySettingHour: fields.startSeconds / 3600,
            minute: fields.startSeconds % 3600 / 60,
            second: fields.startSeconds % 60,
            of: dayStart,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? dayStart.addingTimeInterval(TimeInterval(fields.startSeconds))
        let end = start.addingTimeInterval(TimeInterval(fields.durationSeconds))
        return (start, end)
    }

    enum Field { case start, end, duration }

    /// the text the editor shows for `field`: HH:MM for start and end, HH:MM:SS for duration.
    static func text(_ field: Field, of fields: Fields) -> String {
        switch field {
        case .start: return formatHHMM(fields.startSeconds)
        case .end: return formatHHMM(fields.endSeconds)
        case .duration: return formatHHMMSS(fields.durationSeconds)
        }
    }

    /// apply `text` as an edit of `field`; text that `fields` already shows, or that does not parse, changes nothing.
    static func commit(_ text: String, to field: Field, of fields: Fields) -> Fields {
        guard text != self.text(field, of: fields) else { return fields }
        switch field {
        case .start: return parseHHMM(text).map { withStart(fields, seconds: $0) } ?? fields
        case .end: return parseHHMM(text).map { withEnd(fields, seconds: $0) } ?? fields
        case .duration: return parseHHMMSS(text).map { withDuration(fields, seconds: $0) } ?? fields
        }
    }

    /// commit each text that differs from what `fields` shows, in the order start, end, duration.
    static func commit(start: String, end: String, duration: String, to fields: Fields) -> Fields {
        var edited = fields
        for (field, text) in [(Field.start, start), (.end, end), (.duration, duration)] where text != self.text(field, of: fields) {
            edited = commit(text, to: field, of: edited)
        }
        return edited
    }

    /// resolve fields edited from the entry `start`-`end`; while they still equal `fields(start:end:)`, the entry's own dates come back.
    static func resolve(_ fields: Fields, editing start: Date, end: Date?, calendar: Calendar = .current) -> (start: Date, end: Date?) {
        if fields == self.fields(start: start, end: end, calendar: calendar) { return (start, end) }
        let resolved = resolve(fields, baseDate: start, calendar: calendar)
        return (resolved.start, resolved.end)
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

    private static func clampTimeOfDay(_ seconds: Int) -> Int {
        let mod = ((seconds % secondsPerDay) + secondsPerDay) % secondsPerDay
        return mod
    }

    private static func timeOfDaySeconds(_ date: Date, calendar: Calendar) -> Int {
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)
    }
}
