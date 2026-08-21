import Foundation

struct ProjectTotal: Identifiable, Equatable {
    let id: String
    let name: String
    let seconds: Int
}

struct DayTotal: Identifiable, Equatable {
    let id: Date
    let date: Date
    let seconds: Int
}

enum ReportBuilder {
    /// seconds of `entry` that fall inside `rangeStart..<rangeEnd`, treating a
    /// running entry as ending at `now`.
    static func overlapSeconds(
        entry: TimeEntry,
        rangeStart: Date,
        rangeEnd: Date,
        now: Date
    ) -> Int {
        let end = entry.end ?? now
        let overlapStart = max(entry.start, rangeStart)
        let overlapEnd = min(end, rangeEnd)
        return max(0, Int(overlapEnd.timeIntervalSince(overlapStart).rounded(.down)))
    }

    static func totalSeconds(
        entries: [TimeEntry],
        rangeStart: Date,
        rangeEnd: Date,
        now: Date
    ) -> Int {
        entries.reduce(0) { sum, entry in
            sum + overlapSeconds(entry: entry, rangeStart: rangeStart, rangeEnd: rangeEnd, now: now)
        }
    }

    /// seconds of `entries` that fall inside the calendar day containing `day`.
    static func dayTotalSeconds(
        entries: [TimeEntry],
        day: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Int {
        let range = TimeMath.dayRange(for: day, calendar: calendar)
        return totalSeconds(
            entries: entries,
            rangeStart: range.lowerBound,
            rangeEnd: range.upperBound,
            now: now
        )
    }

    static func dailyTotals(
        entries: [TimeEntry],
        rangeStart: Date,
        rangeEnd: Date,
        now: Date,
        projectNameForId: (String) -> String
    ) -> [ProjectTotal] {
        var totals: [String: Int] = [:]
        for entry in entries {
            totals[entry.projectId, default: 0] += overlapSeconds(
                entry: entry,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                now: now
            )
        }

        return totals
            .map { ProjectTotal(id: $0.key, name: projectNameForId($0.key), seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    static func weeklyTotals(
        entries: [TimeEntry],
        weekStart: Date,
        now: Date,
        calendar: Calendar
    ) -> [DayTotal] {
        var results: [DayTotal] = []
        for offset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: weekStart),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }
            let seconds = totalSeconds(
                entries: entries,
                rangeStart: dayStart,
                rangeEnd: dayEnd,
                now: now
            )
            results.append(DayTotal(id: dayStart, date: dayStart, seconds: seconds))
        }
        return results
    }
}
