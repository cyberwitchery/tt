import Foundation

struct WeekChartModel {
    struct Bar: Identifiable {
        let id: Date
        let seconds: Int
        let isToday: Bool
        let height: Double
        let label: String
    }

    let bars: [Bar]

    init(totals: [DayTotal], days: DayCalendar) {
        let today = days.today.range
        let maximum = max(1, totals.map(\.seconds).max() ?? 1)
        bars = totals.map { total in
            let seconds = max(0, total.seconds)
            let height = seconds == 0 ? 0 : max(2, min(1, Double(seconds) / Double(maximum)) * 36)
            let label: String
            if seconds == 0 { label = "—" }
            else if seconds >= 3600 { label = "\(seconds / 3600)h" }
            else { label = "\(seconds / 60)m" }
            return Bar(id: total.date, seconds: seconds, isToday: today.contains(total.date), height: height, label: label)
        }
    }
}
