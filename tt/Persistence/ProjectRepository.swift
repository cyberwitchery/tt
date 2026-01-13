import Foundation
import GRDB

final class ProjectRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    func fetchAllActive() throws -> [Project] {
        try dbQueue.read { db in
            try Project
                .filter(Column("archived") == false)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func fetchAll() throws -> [Project] {
        try dbQueue.read { db in
            try Project
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func insert(_ project: Project) throws {
        try dbQueue.write { db in
            try project.insert(db)
        }
    }

    func archive(projectId: String) throws {
        try dbQueue.write { db in
            try Project
                .filter(Column("id") == projectId)
                .updateAll(db, Column("archived").set(to: true))
        }
    }

    func ensureDefaultProject() throws -> Project {
        if let existing = try fetchAllActive().first {
            return existing
        }

        let project = Project(name: "default")
        try insert(project)
        return project
    }
}
