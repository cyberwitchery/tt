import Foundation
import GRDB

struct Project: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "projects"

    var id: String
    var name: String
    var archived: Bool
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String, archived: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.archived = archived
        self.createdAt = createdAt
    }
}

struct TimeEntry: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "time_entries"

    var id: String
    var projectId: String
    var start: Date
    var end: Date?
    var note: String?

    init(
        id: String = UUID().uuidString,
        projectId: String,
        start: Date,
        end: Date? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.start = start
        self.end = end
        self.note = note
    }
}
