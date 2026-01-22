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
}
