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
    static func dailyTotals(
        entries: [TimeEntry],
        rangeStart: Date,
        rangeEnd: Date,
        now: Date,
        projectNameForId: (String) -> String
    ) -> [ProjectTotal] {
        var totals: [String: Int] = [:]
        for entry in entries {
            let end = entry.end ?? now
            let overlapStart = max(entry.start, rangeStart)
            let overlapEnd = min(end, rangeEnd)
            let seconds = max(0, Int(overlapEnd.timeIntervalSince(overlapStart).rounded(.down)))
            totals[entry.projectId, default: 0] += seconds
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
            var seconds = 0
            for entry in entries {
                let end = entry.end ?? now
                let overlapStart = max(entry.start, dayStart)
                let overlapEnd = min(end, dayEnd)
                seconds += max(0, Int(overlapEnd.timeIntervalSince(overlapStart).rounded(.down)))
            }
            results.append(DayTotal(id: dayStart, date: dayStart, seconds: seconds))
        }
        return results
    }
}
