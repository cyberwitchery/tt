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

        return migrator
    }
}
