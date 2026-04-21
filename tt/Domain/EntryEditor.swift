import Foundation

/// Pure HH:MM / HH:MM:SS bound-field math for the inline entry editor.
///
/// Fields are `startSeconds`, `endSeconds` (both 0..86399, expected to be
/// minute-aligned when edited via the UI) and `durationSeconds` (0..86400).
/// Cross-midnight is modeled by adding 24h to the duration when `end < start`;
/// that's the only cross-midnight case the editor supports.
enum EntryEditor {
    struct Fields: Equatable {
        var startSeconds: Int
        var endSeconds: Int
        var durationSeconds: Int
    }

    static let secondsPerDay = 86_400

    /// Build initial fields from an entry's start and optional end, using the
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

    /// Edit `start`: hold duration, recompute end.
    static func withStart(_ fields: Fields, seconds: Int) -> Fields {
        var f = fields
        f.startSeconds = clampTimeOfDay(seconds)
        f.endSeconds = (f.startSeconds + f.durationSeconds) % secondsPerDay
        return f
    }

    /// Edit `end`: hold start, recompute duration (+24h if crossed midnight).
    static func withEnd(_ fields: Fields, seconds: Int) -> Fields {
        var f = fields
        f.endSeconds = clampTimeOfDay(seconds)
        var dur = f.endSeconds - f.startSeconds
        if dur < 0 { dur += secondsPerDay }
        f.durationSeconds = dur
        return f
    }

    /// Edit `duration`: hold start, recompute end (wrapping modulo 24h).
    static func withDuration(_ fields: Fields, seconds: Int) -> Fields {
        var f = fields
        f.durationSeconds = max(0, min(secondsPerDay, seconds))
        f.endSeconds = (f.startSeconds + f.durationSeconds) % secondsPerDay
        return f
    }

    /// Resolve fields back to `(start, end)` Date values anchored to `baseDate`'s day.
    /// The returned `end` may fall on the next calendar day if the duration crosses midnight.
    static func resolve(_ fields: Fields, baseDate: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let dayStart = calendar.startOfDay(for: baseDate)
        let start = dayStart.addingTimeInterval(TimeInterval(fields.startSeconds))
        let end = start.addingTimeInterval(TimeInterval(fields.durationSeconds))
        return (start, end)
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
