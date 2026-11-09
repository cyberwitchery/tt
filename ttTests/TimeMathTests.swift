import XCTest
@testable import tt

final class TimeMathTests: XCTestCase {
    func testCompactDurationFormats() {
        for (seconds, hm, idle) in [(-1, "00:00", "0:00"), (0, "00:00", "0:00"), (61, "00:01", "0:01"), (3660, "01:01", "1:01"), (360_000, "100:00", "100:00")] {
            XCTAssertEqual(TimeMath.formatHM(seconds: seconds), hm)
            XCTAssertEqual(TimeMath.formatIdle(seconds: seconds), idle)
        }
    }

    // MARK: - durationSeconds

    func testDurationAcrossDSTUsesAbsoluteTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let start = calendar.date(from: DateComponents(year: 2023, month: 11, day: 5, hour: 0, minute: 30))!
        let end = calendar.date(from: DateComponents(year: 2023, month: 11, day: 5, hour: 2, minute: 30))!

        let seconds = TimeMath.durationSeconds(start: start, end: end)
        XCTAssertEqual(seconds, 3 * 3600)
    }

    func testDurationSecondsWithExplicitEnd() {
        let start = Date()
        let end = start.addingTimeInterval(3600)

        let seconds = TimeMath.durationSeconds(start: start, end: end)
        XCTAssertEqual(seconds, 3600)
    }

    func testDurationSecondsWithNilEndUsesNow() {
        let start = Date().addingTimeInterval(-60)
        let now = Date()

        let seconds = TimeMath.durationSeconds(start: start, end: nil, now: now)
        XCTAssertEqual(seconds, 60)
    }

    func testDurationSecondsWithEndBeforeStartReturnsZero() {
        let start = Date()
        let end = start.addingTimeInterval(-100)

        let seconds = TimeMath.durationSeconds(start: start, end: end)
        XCTAssertEqual(seconds, 0)
    }

    func testDurationSecondsRoundsDown() {
        let start = Date()
        let end = start.addingTimeInterval(59.9)

        let seconds = TimeMath.durationSeconds(start: start, end: end)
        XCTAssertEqual(seconds, 59)
    }

    // MARK: - formatHMS

    func testFormatHMS() {
        XCTAssertEqual(TimeMath.formatHMS(seconds: 0), "00:00:00")
        XCTAssertEqual(TimeMath.formatHMS(seconds: 59), "00:00:59")
        XCTAssertEqual(TimeMath.formatHMS(seconds: 61), "00:01:01")
        XCTAssertEqual(TimeMath.formatHMS(seconds: 3661), "01:01:01")
    }

    func testFormatHMSWithLargeValues() {
        XCTAssertEqual(TimeMath.formatHMS(seconds: 86400), "24:00:00")
        XCTAssertEqual(TimeMath.formatHMS(seconds: 359999), "99:59:59")
    }

    func testFormatHMSWithNegativeValuesClampsToZero() {
        XCTAssertEqual(TimeMath.formatHMS(seconds: -1), "00:00:00")
        XCTAssertEqual(TimeMath.formatHMS(seconds: -3600), "00:00:00")
    }
}

final class DayCalendarTests: XCTestCase {
    func testTodayAndMonthStartUseTheInjectedClock() {
        let clock = TestClock()
        clock.calendar = Calendar(identifier: .gregorian)
        clock.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        clock.now = Date.from(year: 2026, month: 3, day: 31, hour: 23)
        let days = clock.days

        XCTAssertEqual(days.today.start, Date.from(year: 2026, month: 3, day: 31))
        XCTAssertEqual(days.monthStart(containing: days.now), Date.from(year: 2026, month: 3, day: 1))
        XCTAssertTrue(days.isToday(clock.now))
        XCTAssertFalse(days.isToday(Date.from(year: 2026, month: 4, day: 1)))

        clock.now = Date.from(year: 2026, month: 4, day: 1)
        XCTAssertEqual(days.today.start, clock.now)
        XCTAssertEqual(days.monthStart(containing: days.now), clock.now)
    }

    func testRollingWeekUsesWholeDaysAcrossClockChanges() {
        for (zone, month, day, hours) in [("Europe/Berlin", 3, 29, 23), ("Europe/Berlin", 10, 25, 25), ("America/Santiago", 9, 6, 23)] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            let days = DayCalendar(calendar: { calendar })

            let week = days.week(endingOn: date)

            XCTAssertEqual(week.days.count, 7, zone)
            XCTAssertEqual(week.days.last?.range, days.day(containing: date).range, zone)
            XCTAssertEqual(week.range.upperBound.timeIntervalSince(week.range.lowerBound), TimeInterval((6 * 24 + hours) * 3600), zone)
            for (previous, next) in zip(week.days, week.days.dropFirst()) {
                XCTAssertEqual(previous.end, next.start, zone)
            }
        }
    }

    func testDaysBetweenCountsCivilDatesAcrossMissingMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santiago")!
        let days = DayCalendar(calendar: { calendar })
        let before = days.day(containing: calendar.date(from: DateComponents(year: 2024, month: 9, day: 8, hour: 23))!)
        let after = days.nextDay(after: before)

        XCTAssertEqual(days.daysBetween(before, and: after), 1)
        XCTAssertEqual(days.daysBetween(after, and: before), -1)
        XCTAssertEqual(days.day(byAdding: -1, to: after), before)
    }

    func testDayRangeCoversTheWholeCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let range = DayCalendar(calendar: { calendar }).day(containing: Date.from(year: 2024, month: 1, day: 2, hour: 17)).range

        XCTAssertEqual(range.lowerBound, Date.from(year: 2024, month: 1, day: 2))
        XCTAssertEqual(range.upperBound, Date.from(year: 2024, month: 1, day: 3))
    }

    func testDayRangeSpansTwentyFiveHoursWhenTheClocksGoBack() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!

        let range = DayCalendar(calendar: { calendar }).day(containing: Date.from(year: 2024, month: 10, day: 27, hour: 12)).range

        XCTAssertEqual(range.upperBound.timeIntervalSince(range.lowerBound), 25 * 3600)
    }

    func testDayRangeFromThroughCoversExactlyThePickedDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        func berlin(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        }

        let rows: [(name: String, first: Date, last: Date, lower: Date, upper: Date)] = [
            ("end date with a time of day", berlin(10, 14), berlin(10, 14, 14, 37), berlin(10, 14), berlin(10, 15)),
            ("reversed dates", berlin(10, 14), berlin(10, 12, 14, 37), berlin(10, 12), berlin(10, 15)),
            ("fall-back last day", berlin(10, 19), berlin(10, 25), berlin(10, 19), berlin(10, 26)),
            ("spring-forward last day", berlin(3, 23), berlin(3, 29), berlin(3, 23), berlin(3, 30)),
            ("plain multi-day span", berlin(10, 5, 9, 30), berlin(10, 9, 17, 45), berlin(10, 5), berlin(10, 10)),
        ]

        for row in rows {
            let range = DayCalendar(calendar: { calendar }).range(from: row.first, through: row.last)
            XCTAssertEqual(range.lowerBound, row.lower, row.name)
            XCTAssertEqual(range.upperBound, row.upper, row.name)
        }
    }

    func testDayRangeOfADayWithoutAMidnightEndsAtTheNextMidnight() {
        let rows: [(zone: String, year: Int, month: Int, day: Int)] = [
            ("America/Santiago", 2024, 9, 8),
            ("America/Havana", 2024, 3, 10),
        ]

        for row in rows {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: row.zone)!
            func at(_ day: Int, _ hour: Int) -> Date {
                calendar.date(from: DateComponents(year: row.year, month: row.month, day: day, hour: hour))!
            }

            let range = DayCalendar(calendar: { calendar }).day(containing: at(row.day, 12)).range

            XCTAssertEqual(range.lowerBound, at(row.day, 1), row.zone)
            XCTAssertEqual(range.upperBound, at(row.day + 1, 0), row.zone)
        }
    }
}
