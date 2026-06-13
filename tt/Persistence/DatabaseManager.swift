import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folderURL = appSupport.appendingPathComponent("tt", isDirectory: true)

        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let dbURL = folderURL.appendingPathComponent("tt.sqlite")
        dbQueue = try! DatabaseQueue(path: dbURL.path)

        try? migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createProjects") { db in
            try db.create(table: Project.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("createTimeEntries") { db in
            try db.create(table: TimeEntry.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("projectId", .text).notNull().indexed()
                t.column("start", .datetime).notNull()
                t.column("end", .datetime)
                t.column("note", .text)
            }
        }

        migrator.registerMigration("createCOCOMOParams") { db in
            try db.create(table: COCOMOParams.databaseTableName, ifNotExists: true) { t in
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

        return migrator
    }
}
