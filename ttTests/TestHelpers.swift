import Foundation
import XCTest
import GRDB
@testable import tt

final class TestClock {
    var now = Date()
    var calendar = Calendar.current

    var days: DayCalendar { DayCalendar(calendar: { self.calendar }, now: { self.now }) }
}

enum TestDatabase {
    static func makeInMemory() throws -> DatabaseQueue {
        try DatabaseManager().dbQueue
    }
}


class TrackerTestCase: XCTestCase {
    var dbQueue: DatabaseQueue!
    var projectRepository: ProjectRepository!
    var timeEntryRepository: TimeEntryRepository!
    var tracker: TimeTracker!
    var clock = TestClock()

    override func setUp() {
        super.setUp()
        clock = TestClock()
        dbQueue = try! TestDatabase.makeInMemory()
        projectRepository = ProjectRepository(dbQueue: dbQueue)
        timeEntryRepository = TimeEntryRepository(dbQueue: dbQueue)
        tracker = TimeTracker(projectRepository: projectRepository, timeEntryRepository: timeEntryRepository, days: clock.days)
    }

    override func tearDown() {
        tracker = nil
        timeEntryRepository = nil
        projectRepository = nil
        dbQueue = nil
        super.tearDown()
    }
}

extension Date {
    static func from(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
