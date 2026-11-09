import XCTest
@testable import tt

final class PresentationLogicTests: XCTestCase {
    func testKeyboardMapAndTextFocus() {
        let keys: [(UInt16, KeyboardShortcut)] = [(49, .space), (45, .n), (35, .p), (14, .e), (17, .t), (53, .escape), (123, .leftArrow), (124, .rightArrow)]
        for (code, shortcut) in keys {
            XCTAssertEqual(KeyboardShortcut(keyCode: code, textFocused: false), shortcut)
            XCTAssertEqual(KeyboardShortcut(keyCode: code, textFocused: true), shortcut == .escape ? .escape : nil)
        }
        XCTAssertNil(KeyboardShortcut(keyCode: 0, textFocused: false))
    }

    func testWeekChartUsesTheInjectedTodayAndScalesBars() {
        let clock = TestClock()
        clock.calendar = Calendar(identifier: .gregorian)
        clock.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        clock.now = Date.from(year: 2026, month: 1, day: 7, hour: 12)
        let seconds = [0, 1, 60, 1800, 3600, 0, 0]
        let totals = zip(clock.days.week(endingOn: clock.now).days, seconds).map { DayTotal(id: $0.start, date: $0.start, seconds: $1) }
        let model = WeekChartModel(totals: totals, days: clock.days)
        XCTAssertEqual(model.bars.map(\.isToday), [false, false, false, false, false, false, true])
        XCTAssertEqual(model.bars.map(\.height), [0, 2, 2, 18, 36, 0, 0])
        XCTAssertEqual(model.bars.map(\.label), ["—", "0m", "1m", "30m", "1h", "—", "—"])
        XCTAssertTrue(WeekChartModel(totals: [], days: clock.days).bars.isEmpty)
    }
}
