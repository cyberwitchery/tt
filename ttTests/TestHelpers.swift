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

        migrator.registerMigration("createCOCOMOParams") { db in
            try db.create(table: COCOMOParams.databaseTableName) { t in
                t.column("projectId", .text).primaryKey()
                t.column("sloc", .integer).notNull().defaults(to: 0)
                t.column("prec", .integer).notNull().defaults(to: 2)
                t.column("flex", .integer).notNull().defaults(to: 2)
                t.column("resl", .integer).notNull().defaults(to: 2)
                t.column("team", .integer).notNull().defaults(to: 2)
                t.column("pmat", .integer).notNull().defaults(to: 2)
                t.column("rely", .integer).notNull().defaults(to: 2)
                t.column("data", .integer).notNull().defaults(to: 2)
                t.column("cplx", .integer).notNull().defaults(to: 2)
                t.column("ruse", .integer).notNull().defaults(to: 2)
                t.column("docu", .integer).notNull().defaults(to: 2)
                t.column("time", .integer).notNull().defaults(to: 2)
                t.column("stor", .integer).notNull().defaults(to: 2)
                t.column("pvol", .integer).notNull().defaults(to: 2)
                t.column("acap", .integer).notNull().defaults(to: 2)
                t.column("pcap", .integer).notNull().defaults(to: 2)
                t.column("pcon", .integer).notNull().defaults(to: 2)
                t.column("apex", .integer).notNull().defaults(to: 2)
                t.column("plex", .integer).notNull().defaults(to: 2)
                t.column("ltex", .integer).notNull().defaults(to: 2)
                t.column("tool", .integer).notNull().defaults(to: 2)
                t.column("site", .integer).notNull().defaults(to: 2)
                t.column("sced", .integer).notNull().defaults(to: 2)
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
