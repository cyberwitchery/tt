import Foundation
import GRDB

final class TimeEntryRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    func insertRunning(entry: TimeEntry) throws {
        try dbQueue.write { db in
            try entry.insert(db)
        }
    }

    func stopRunning(entry: TimeEntry, end: Date) throws -> TimeEntry {
        var updated = entry
        updated.end = end
        try dbQueue.write { db in
            try updated.update(db)
        }
        return updated
    }

    func get(id: String) throws -> TimeEntry? {
        try dbQueue.read { db in
            try TimeEntry
                .filter(Column("id") == id)
                .fetchOne(db)
        }
    }

    func update(_ entry: TimeEntry) throws {
        try dbQueue.write { db in
            try entry.update(db)
        }
    }

    func delete(id: String) throws {
        try dbQueue.write { db in
            try TimeEntry.filter(Column("id") == id).deleteAll(db)
        }
    }

    func fetchMostRecentlyEnded() throws -> TimeEntry? {
        try dbQueue.read { db in
            try TimeEntry
                .filter(Column("end") != nil)
                .order(Column("end").desc)
                .fetchOne(db)
        }
    }

    func fetchRunning() throws -> TimeEntry? {
        try dbQueue.read { db in
            try TimeEntry
                .filter(Column("end") == nil)
                .order(Column("start").desc)
                .fetchOne(db)
        }
    }

    func fetchEntriesForToday(calendar: Calendar = .current) throws -> [TimeEntry] {
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()

        return try fetchEntries(in: startOfDay..<endOfDay)
    }

    func fetchAll() throws -> [TimeEntry] {
        try dbQueue.read { db in
            try TimeEntry
                .order(Column("start").desc)
                .fetchAll(db)
        }
    }

    func fetchCompletedTotalsByProject() throws -> [String: Int] {
        let entries = try dbQueue.read { db in
            try TimeEntry
                .filter(Column("end") != nil)
                .fetchAll(db)
        }
        var totals: [String: Int] = [:]
        for entry in entries {
            guard let end = entry.end else { continue }
            totals[entry.projectId, default: 0] += TimeMath.durationSeconds(start: entry.start, end: end)
        }
        return totals
    }

    func fetchEntries(in range: Range<Date>) throws -> [TimeEntry] {
        let rangeStart = range.lowerBound
        let rangeEnd = range.upperBound
        let startColumn = Column("start")
        let endColumn = Column("end")

        return try dbQueue.read { db in
            try TimeEntry
                .filter(startColumn < rangeEnd && (endColumn == nil || endColumn > rangeStart))
                .order(startColumn.desc)
                .fetchAll(db)
        }
    }

    func resolveMultipleRunningEntries() throws {
        try dbQueue.write { db in
            let running = try TimeEntry
                .filter(Column("end") == nil)
                .order(Column("start").desc)
                .fetchAll(db)

            guard running.count > 1 else { return }
            let keep = running.first

            for entry in running.dropFirst() {
                var closed = entry
                closed.end = keep?.start ?? entry.start
                try closed.update(db)
            }
        }
    }
}
