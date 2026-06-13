import Foundation
import GRDB

final class COCOMORepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    func fetch(projectId: String) throws -> COCOMOParams? {
        try dbQueue.read { db in
            try COCOMOParams
                .filter(Column("projectId") == projectId)
                .fetchOne(db)
        }
    }

    func fetchOrDefault(projectId: String) throws -> COCOMOParams {
        if let existing = try fetch(projectId: projectId) {
            return existing
        }
        return .defaults(projectId: projectId)
    }

    func save(_ params: COCOMOParams) throws {
        try dbQueue.write { db in
            try params.save(db, onConflict: .replace)
        }
    }
}
