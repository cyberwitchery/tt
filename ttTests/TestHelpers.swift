import Foundation
import GRDB
@testable import tt

enum TestDatabase {
    static func makeInMemory() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()

        var migrator = DatabaseMigrator()

        migrator.registerMigration("createProjects") { db in
            try db.create(table: Project.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("createTimeEntries") { db in
            try db.create(table: TimeEntry.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("projectId", .text).notNull().indexed()
                t.column("start", .datetime).notNull()
                t.column("end", .datetime)
                t.column("note", .text)
            }
        }

        try migrator.migrate(dbQueue)
        return dbQueue
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
