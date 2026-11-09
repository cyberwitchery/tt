import XCTest
import AppKit
@testable import tt

final class PresentationLogicTests: XCTestCase {
    @MainActor
    func testKeyHandlerCanConsumeAnEventAndIgnoresOtherWindows() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .titled, backing: .buffered, defer: false)
        let other = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        other.isReleasedWhenClosed = false
        defer { window.close(); other.close() }
        let catcher = KeyCatcherNSView()
        window.contentView = catcher
        var calls = 0
        catcher.handler = { _ in calls += 1; return nil }
        func event(in window: NSWindow) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "p", charactersIgnoringModifiers: "p", isARepeat: false, keyCode: 35)!
        }
        let consumed = event(in: window)
        XCTAssertTrue(consumed.window === window)
        XCTAssertNil(catcher.handle(consumed))
        XCTAssertEqual(calls, 1)
        let passed = event(in: other)
        XCTAssertTrue(catcher.handle(passed) === passed)
        XCTAssertEqual(calls, 1)
    }

    func testKeyboardMapAndTextFocus() {
        let keys: [(UInt16, KeyboardShortcut)] = [(49, .space), (45, .n), (35, .p), (14, .e), (17, .t), (53, .escape), (123, .leftArrow), (124, .rightArrow)]
        for (code, shortcut) in keys {
            XCTAssertEqual(KeyboardShortcut(keyCode: code, textFocused: false), shortcut)
            XCTAssertEqual(KeyboardShortcut(keyCode: code, textFocused: true), shortcut == .escape ? .escape : nil)
        }
        XCTAssertNil(KeyboardShortcut(keyCode: 0, textFocused: false))
        for modifiers: NSEvent.ModifierFlags in [.command, .control, .option] {
            XCTAssertNil(KeyboardShortcut(keyCode: 35, textFocused: false, modifiers: modifiers))
        }
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
