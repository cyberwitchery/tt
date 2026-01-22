import XCTest
@testable import tt

final class TimeMathTests: XCTestCase {
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
