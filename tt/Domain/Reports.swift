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
        day: DayCalendar.Day,
        now: Date
    ) -> Int {
        let range = day.range
        return totalSeconds(
            entries: entries,
            rangeStart: range.lowerBound,
            rangeEnd: range.upperBound,
            now: now
        )
    }

    static func projectTotals(
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

    /// totals clipped to each of the week's calendar days.
    static func dayTotals(
        entries: [TimeEntry],
        week: DayCalendar.Week,
        now: Date
    ) -> [DayTotal] {
        week.days.map { day in
            let seconds = totalSeconds(
                entries: entries,
                rangeStart: day.start,
                rangeEnd: day.end,
                now: now
            )
            return DayTotal(id: day.start, date: day.start, seconds: seconds)
        }
    }
}
