import Foundation
import GRDB

final class DatabaseManager {
    static let shared: Result<DatabaseManager, Error> = Result {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return try DatabaseManager(path: databaseURL(in: support).path)
    }

    let dbQueue: DatabaseQueue

    /// Omitting a path creates an isolated, migrated in-memory database.
    init(path: String = ":memory:") throws {
        dbQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(dbQueue)
    }

    static func databaseURL(in appSupport: URL) throws -> URL {
        let fileManager = FileManager.default
        let folder = appSupport.appendingPathComponent("tt", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("tt.sqlite")
    }

    private static var migrator: DatabaseMigrator {
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
