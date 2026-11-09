import XCTest
import GRDB
@testable import tt

final class DatabaseManagerTests: XCTestCase {
    func testStorageLayoutCreatesTheApplicationFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try DatabaseManager.databaseURL(in: folder)
        XCTAssertEqual(url, folder.appendingPathComponent("tt/tt.sqlite"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        XCTAssertNoThrow(try DatabaseManager(path: url.path))
    }

    func testInMemoryDatabaseRunsProductionMigrations() throws {
        let manager = try DatabaseManager()
        let project = try ProjectRepository(dbQueue: manager.dbQueue).ensureDefaultProject()
        let entry = TimeEntry(projectId: project.id, start: Date(), note: "migrated")
        let entries = TimeEntryRepository(dbQueue: manager.dbQueue)
        try entries.insertRunning(entry: entry)
        XCTAssertEqual(try entries.get(id: entry.id)?.note, "migrated")
        let migrations = try manager.dbQueue.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier") }
        XCTAssertEqual(migrations, ["createProjects", "createTimeEntries"])
        XCTAssertTrue(try DatabaseManager().dbQueue.read { try Project.fetchAll($0).isEmpty })
    }

    func testDiskDatabaseCanBeReopenedWithoutLosingData() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("tt.sqlite").path
        let project: Project
        do {
            let manager = try DatabaseManager(path: path)
            let repository = ProjectRepository(dbQueue: manager.dbQueue)
            _ = try repository.ensureDefaultProject()
            project = try XCTUnwrap(repository.fetchAll().first)
        }
        let reopened = try DatabaseManager(path: path)
        XCTAssertEqual(try ProjectRepository(dbQueue: reopened.dbQueue).fetchAll(), [project])
    }

    func testInvalidPathSurfacesTheOpenError() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("missing/tt.sqlite").path
        XCTAssertThrowsError(try DatabaseManager(path: path))
    }
}
