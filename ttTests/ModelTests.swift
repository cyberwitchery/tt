import XCTest
@testable import tt

final class ModelTests: XCTestCase {
    // MARK: - Project

    func testProjectDefaultValues() {
        let project = Project(name: "test")

        XCTAssertFalse(project.id.isEmpty)
        XCTAssertEqual(project.name, "test")
        XCTAssertFalse(project.archived)
        XCTAssertNotNil(project.createdAt)
    }

    func testProjectEquality() {
        let id = "same-id"
        let createdAt = Date()
        let project1 = Project(id: id, name: "test", createdAt: createdAt)
        let project2 = Project(id: id, name: "test", createdAt: createdAt)
        let project3 = Project(id: "different", name: "test", createdAt: createdAt)

        XCTAssertEqual(project1, project2)
        XCTAssertNotEqual(project1, project3)
    }

    func testProjectWithCustomId() {
        let project = Project(id: "custom-id", name: "test")

        XCTAssertEqual(project.id, "custom-id")
    }

    func testProjectWithArchivedTrue() {
        let project = Project(name: "test", archived: true)

        XCTAssertTrue(project.archived)
    }

    func testProjectWithCustomCreatedAt() {
        let customDate = Date.from(year: 2024, month: 6, day: 15)
        let project = Project(name: "test", createdAt: customDate)

        XCTAssertEqual(project.createdAt, customDate)
    }

    func testProjectIdentifiable() {
        let project = Project(id: "test-id", name: "test")

        XCTAssertEqual(project.id, "test-id")
    }

    func testProjectInequalityByName() {
        let createdAt = Date()
        let project1 = Project(id: "same", name: "name1", createdAt: createdAt)
        let project2 = Project(id: "same", name: "name2", createdAt: createdAt)

        XCTAssertNotEqual(project1, project2)
    }

    func testProjectInequalityByArchived() {
        let createdAt = Date()
        let project1 = Project(id: "same", name: "test", archived: false, createdAt: createdAt)
        let project2 = Project(id: "same", name: "test", archived: true, createdAt: createdAt)

        XCTAssertNotEqual(project1, project2)
    }

    // MARK: - TimeEntry

    func testTimeEntryDefaultValues() {
        let entry = TimeEntry(projectId: "p1", start: Date())

        XCTAssertFalse(entry.id.isEmpty)
        XCTAssertEqual(entry.projectId, "p1")
        XCTAssertNil(entry.end)
        XCTAssertNil(entry.note)
    }

    func testTimeEntryWithAllFields() {
        let start = Date()
        let end = Date().addingTimeInterval(3600)

        let entry = TimeEntry(
            id: "custom-id",
            projectId: "p1",
            start: start,
            end: end,
            note: "test note"
        )

        XCTAssertEqual(entry.id, "custom-id")
        XCTAssertEqual(entry.projectId, "p1")
        XCTAssertEqual(entry.start, start)
        XCTAssertEqual(entry.end, end)
        XCTAssertEqual(entry.note, "test note")
    }

    func testTimeEntryEquality() {
        let id = "same-id"
        let date = Date()

        let entry1 = TimeEntry(id: id, projectId: "p1", start: date)
        let entry2 = TimeEntry(id: id, projectId: "p1", start: date)
        let entry3 = TimeEntry(id: "different", projectId: "p1", start: date)

        XCTAssertEqual(entry1, entry2)
        XCTAssertNotEqual(entry1, entry3)
    }

    func testTimeEntryIdentifiable() {
        let entry = TimeEntry(id: "entry-id", projectId: "p1", start: Date())

        XCTAssertEqual(entry.id, "entry-id")
    }

    func testTimeEntryInequalityByProjectId() {
        let date = Date()
        let entry1 = TimeEntry(id: "same", projectId: "p1", start: date)
        let entry2 = TimeEntry(id: "same", projectId: "p2", start: date)

        XCTAssertNotEqual(entry1, entry2)
    }

    func testTimeEntryInequalityByStart() {
        let entry1 = TimeEntry(id: "same", projectId: "p1", start: Date.from(year: 2024, month: 1, day: 1))
        let entry2 = TimeEntry(id: "same", projectId: "p1", start: Date.from(year: 2024, month: 1, day: 2))

        XCTAssertNotEqual(entry1, entry2)
    }

    func testTimeEntryInequalityByEnd() {
        let date = Date()
        let entry1 = TimeEntry(id: "same", projectId: "p1", start: date, end: nil)
        let entry2 = TimeEntry(id: "same", projectId: "p1", start: date, end: date.addingTimeInterval(3600))

        XCTAssertNotEqual(entry1, entry2)
    }

    func testTimeEntryInequalityByNote() {
        let date = Date()
        let entry1 = TimeEntry(id: "same", projectId: "p1", start: date, note: nil)
        let entry2 = TimeEntry(id: "same", projectId: "p1", start: date, note: "a note")

        XCTAssertNotEqual(entry1, entry2)
    }

    func testTimeEntryMutability() {
        var entry = TimeEntry(projectId: "p1", start: Date())
        let newEnd = Date().addingTimeInterval(3600)

        entry.end = newEnd
        entry.note = "updated"

        XCTAssertEqual(entry.end, newEnd)
        XCTAssertEqual(entry.note, "updated")
    }

    // MARK: - ProjectTotal

    func testProjectTotalInitialization() {
        let total = ProjectTotal(id: "p1", name: "test project", seconds: 3600)

        XCTAssertEqual(total.id, "p1")
        XCTAssertEqual(total.name, "test project")
        XCTAssertEqual(total.seconds, 3600)
    }

    func testProjectTotalEquality() {
        let total1 = ProjectTotal(id: "p1", name: "test", seconds: 3600)
        let total2 = ProjectTotal(id: "p1", name: "test", seconds: 3600)
        let total3 = ProjectTotal(id: "p2", name: "test", seconds: 3600)

        XCTAssertEqual(total1, total2)
        XCTAssertNotEqual(total1, total3)
    }

    // MARK: - DayTotal

    func testDayTotalInitialization() {
        let date = Date.from(year: 2024, month: 1, day: 1)
        let total = DayTotal(id: date, date: date, seconds: 7200)

        XCTAssertEqual(total.id, date)
        XCTAssertEqual(total.date, date)
        XCTAssertEqual(total.seconds, 7200)
    }

    func testDayTotalEquality() {
        let date1 = Date.from(year: 2024, month: 1, day: 1)
        let date2 = Date.from(year: 2024, month: 1, day: 2)

        let total1 = DayTotal(id: date1, date: date1, seconds: 3600)
        let total2 = DayTotal(id: date1, date: date1, seconds: 3600)
        let total3 = DayTotal(id: date2, date: date2, seconds: 3600)

        XCTAssertEqual(total1, total2)
        XCTAssertNotEqual(total1, total3)
    }
}
