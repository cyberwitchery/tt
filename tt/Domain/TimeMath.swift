import Foundation

enum TimeMath {
    static func durationSeconds(start: Date, end: Date) -> Int {
        let seconds = max(0, end.timeIntervalSince(start))
        return Int(seconds.rounded(.down))
    }

    static func durationSeconds(start: Date, end: Date?, now: Date) -> Int {
        durationSeconds(start: start, end: end ?? now)
    }

    static func formatHMS(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    static func formatHM(seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d", value / 3600, value % 3600 / 60)
    }

    static func formatIdle(seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%d:%02d", value / 3600, value % 3600 / 60)
    }

}
