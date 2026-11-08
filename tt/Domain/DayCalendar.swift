import Foundation

/// Calendar boundaries and wall-clock dates for the tracker, editor and reports.
struct DayCalendar {
    struct Day: Equatable {
        let range: Range<Date>
        fileprivate let civilDate: DateComponents

        var start: Date { range.lowerBound }
        var end: Date { range.upperBound }
    }

    struct Week {
        let days: [Day]
        var range: Range<Date> { days[0].start..<days[6].end }

        fileprivate init(days: [Day]) { self.days = days }
    }

    private let calendarProvider: () -> Calendar
    private let nowProvider: () -> Date

    init(calendar: @escaping () -> Calendar = { .autoupdatingCurrent }, now: @escaping () -> Date = Date.init) {
        calendarProvider = calendar
        nowProvider = now
    }

    var calendar: Calendar { calendarProvider() }
    var now: Date { nowProvider() }
    var today: Day { day(containing: now) }

    func day(containing date: Date) -> Day {
        let calendar = calendar
        let interval = calendar.dateInterval(of: .day, for: date)!
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        var civilDate = gregorian.dateComponents([.era, .year, .month, .day], from: date)
        civilDate.hour = 12
        return Day(range: interval.start..<interval.end, civilDate: civilDate)
    }

    func day(byAdding offset: Int, to day: Day) -> Day {
        let date = calendar.date(byAdding: .day, value: offset, to: day.start)!
        return self.day(containing: date)
    }

    func nextDay(after day: Day) -> Day {
        self.day(containing: day.end)
    }

    func range(from first: Date, through last: Date) -> Range<Date> {
        day(containing: min(first, last)).start..<day(containing: max(first, last)).end
    }

    /// The rolling seven calendar days ending on `date`'s day.
    func week(endingOn date: Date) -> Week {
        week(startingOn: day(byAdding: -6, to: day(containing: date)).start)
    }

    func week(startingOn date: Date) -> Week {
        var days = [day(containing: date)]
        for _ in 1..<7 { days.append(nextDay(after: days.last!)) }
        return Week(days: days)
    }

    /// Count civil dates, even if the time zone or calendar changed between reads.
    func daysBetween(_ first: Day, and last: Day) -> Int {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        return gregorian.dateComponents([.day], from: first.civilDate, to: last.civilDate).day!
    }

    func monthStart(containing date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    func isToday(_ date: Date) -> Bool {
        today.range.contains(date)
    }

    func timeOfDaySeconds(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return parts.hour! * 3600 + parts.minute! * 60 + parts.second!
    }

    /// A skipped hour resolves to the end of the gap; a repeated hour to its first occurrence.
    func date(at seconds: Int, on day: Day) -> Date {
        let clockSeconds = ((seconds % 86_400) + 86_400) % 86_400
        return calendar.date(
            bySettingHour: clockSeconds / 3600,
            minute: clockSeconds % 3600 / 60,
            second: clockSeconds % 60,
            of: day.start,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )!
    }

    func end(at seconds: Int, after start: Date) -> Date {
        let day = day(containing: start)
        let end = date(at: seconds, on: day)
        return end < start ? date(at: seconds, on: nextDay(after: day)) : end
    }

    func nextDay(atTimeOf date: Date) -> Date {
        let fraction = date.timeIntervalSinceReferenceDate - floor(date.timeIntervalSinceReferenceDate)
        return self.date(at: timeOfDaySeconds(date), on: nextDay(after: day(containing: date)))
            .addingTimeInterval(fraction)
    }
}
