import Foundation

enum TimeMath {
    static func durationSeconds(start: Date, end: Date? = nil, now: Date = Date()) -> Int {
        let effectiveEnd = end ?? now
        let seconds = max(0, effectiveEnd.timeIntervalSince(start))
        return Int(seconds.rounded(.down))
    }

    /// the calendar day `date` falls in, as a half-open range.
    static func dayRange(for date: Date, calendar: Calendar = .current) -> Range<Date> {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return start..<end
    }

    static func formatHMS(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
