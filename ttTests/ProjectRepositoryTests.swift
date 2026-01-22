import XCTest
import GRDB
@testable import tt

final class ProjectRepositoryTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    var repository: ProjectRepository!

    override func setUp() {
        super.setUp()
        dbQueue = try! TestDatabase.makeInMemory()
        repository = ProjectRepository(dbQueue: dbQueue)
    }

    override func tearDown() {
        dbQueue = nil
        repository = nil
        super.tearDown()
    }

    func testInsertAndFetchAll() throws {
        let project = Project(name: "test project")
        try repository.insert(project)

        let fetched = try repository.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].name, "test project")
        XCTAssertFalse(fetched[0].archived)
    }

    func testFetchAllActiveExcludesArchived() throws {
        let active = Project(name: "active")
        let archived = Project(name: "archived", archived: true)

        try repository.insert(active)
        try repository.insert(archived)

        let allActive = try repository.fetchAllActive()
        XCTAssertEqual(allActive.count, 1)
        XCTAssertEqual(allActive[0].name, "active")

        let all = try repository.fetchAll()
        XCTAssertEqual(all.count, 2)
    }

    func testArchiveProject() throws {
        let project = Project(name: "to archive")
        try repository.insert(project)

        try repository.archive(projectId: project.id)

        let fetched = try repository.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertTrue(fetched[0].archived)

        let active = try repository.fetchAllActive()
        XCTAssertEqual(active.count, 0)
    }

    func testEnsureDefaultProjectCreatesWhenEmpty() throws {
        let project = try repository.ensureDefaultProject()

        XCTAssertEqual(project.name, "default")

        let all = try repository.fetchAll()
        XCTAssertEqual(all.count, 1)
    }

    func testEnsureDefaultProjectReturnsExistingWhenPresent() throws {
        let existing = Project(name: "my project")
        try repository.insert(existing)

        let returned = try repository.ensureDefaultProject()

        XCTAssertEqual(returned.id, existing.id)
        XCTAssertEqual(returned.name, "my project")

        let all = try repository.fetchAll()
        XCTAssertEqual(all.count, 1)
    }

    func testFetchAllOrdersByCreatedAt() throws {
        let older = Project(
            name: "older",
            createdAt: Date.from(year: 2024, month: 1, day: 1)
        )
        let newer = Project(
            name: "newer",
            createdAt: Date.from(year: 2024, month: 1, day: 2)
        )

        try repository.insert(newer)
        try repository.insert(older)

        let fetched = try repository.fetchAll()
        XCTAssertEqual(fetched[0].name, "older")
        XCTAssertEqual(fetched[1].name, "newer")
    }

    // MARK: - Empty Database

    func testFetchAllOnEmptyDatabase() throws {
        let fetched = try repository.fetchAll()
        XCTAssertTrue(fetched.isEmpty)
    }

    func testFetchAllActiveOnEmptyDatabase() throws {
        let fetched = try repository.fetchAllActive()
        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - Archive Non-Existent

    func testArchiveNonExistentProjectDoesNotThrow() throws {
        XCTAssertNoThrow(try repository.archive(projectId: "non-existent-id"))
    }

    // MARK: - Multiple Projects

    func testInsertMultipleProjects() throws {
        let project1 = Project(name: "project 1")
        let project2 = Project(name: "project 2")
        let project3 = Project(name: "project 3")

        try repository.insert(project1)
        try repository.insert(project2)
        try repository.insert(project3)

        let fetched = try repository.fetchAll()
        XCTAssertEqual(fetched.count, 3)
    }

    func testFetchAllActiveOrdersByCreatedAt() throws {
        let older = Project(
            name: "older",
            createdAt: Date.from(year: 2024, month: 1, day: 1)
        )
        let newer = Project(
            name: "newer",
            createdAt: Date.from(year: 2024, month: 1, day: 2)
        )

        try repository.insert(newer)
        try repository.insert(older)

        let fetched = try repository.fetchAllActive()
        XCTAssertEqual(fetched[0].name, "older")
        XCTAssertEqual(fetched[1].name, "newer")
    }

    // MARK: - Ensure Default With Archived Only

    func testEnsureDefaultProjectCreatesWhenOnlyArchivedExist() throws {
        let archived = Project(name: "archived", archived: true)
        try repository.insert(archived)

        let project = try repository.ensureDefaultProject()

        XCTAssertEqual(project.name, "default")

        let all = try repository.fetchAll()
        XCTAssertEqual(all.count, 2)

        let active = try repository.fetchAllActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].name, "default")
    }
}
