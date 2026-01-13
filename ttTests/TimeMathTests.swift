import XCTest
@testable import tt

final class TimeMathTests: XCTestCase {
    func testDurationAcrossDSTUsesAbsoluteTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let start = calendar.date(from: DateComponents(year: 2023, month: 11, day: 5, hour: 0, minute: 30))!
        let end = calendar.date(from: DateComponents(year: 2023, month: 11, day: 5, hour: 2, minute: 30))!

        let seconds = TimeMath.durationSeconds(start: start, end: end)
        XCTAssertEqual(seconds, 3 * 3600)
    }

    func testFormatHMS() {
        XCTAssertEqual(TimeMath.formatHMS(seconds: 0), "00:00:00")
        XCTAssertEqual(TimeMath.formatHMS(seconds: 59), "00:00:59")
        XCTAssertEqual(TimeMath.formatHMS(seconds: 61), "00:01:01")
        XCTAssertEqual(TimeMath.formatHMS(seconds: 3661), "01:01:01")
    }
}
