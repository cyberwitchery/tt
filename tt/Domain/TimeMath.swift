import Foundation

enum TimeMath {
    static func durationSeconds(start: Date, end: Date? = nil, now: Date = Date()) -> Int {
        let effectiveEnd = end ?? now
        let seconds = max(0, effectiveEnd.timeIntervalSince(start))
        return Int(seconds.rounded(.down))
    }

    static func formatHMS(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
