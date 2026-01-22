import XCTest
@testable import tt

final class CSVExporterTests: XCTestCase {
    // MARK: - Basic Export

    func testExportEscapesAndUsesNowForRunning() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2024, month: 2, day: 1, hour: 10))!
        let now = calendar.date(from: DateComponents(year: 2024, month: 2, day: 1, hour: 11, minute: 5))!

        let entry = TimeEntry(
            projectId: "p1",
            start: start,
            end: nil,
            note: "hello, \"world\""
        )

        let csv = CSVExporter.buildCSV(
            entries: [entry],
            projectNames: ["p1": "alpha"],
            now: now
        )

        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "project,start,end,duration_seconds,note")

        let expectedDuration = 3900
        XCTAssertTrue(lines[1].contains(",\(expectedDuration),"))
        XCTAssertTrue(lines[1].contains("\"hello, \"\"world\"\"\""))
    }

    func testExportEmptyEntries() {
        let csv = CSVExporter.buildCSV(
            entries: [],
            projectNames: [:],
            now: Date()
        )

        XCTAssertEqual(csv, "project,start,end,duration_seconds,note\n")
    }

    func testExportMultipleEntries() {
        let start1 = Date.from(year: 2024, month: 1, day: 1, hour: 9)
        let end1 = Date.from(year: 2024, month: 1, day: 1, hour: 10)
        let start2 = Date.from(year: 2024, month: 1, day: 1, hour: 11)
        let end2 = Date.from(year: 2024, month: 1, day: 1, hour: 12)

        let entries = [
            TimeEntry(projectId: "p1", start: start1, end: end1, note: "first"),
            TimeEntry(projectId: "p2", start: start2, end: end2, note: "second")
        ]

        let csv = CSVExporter.buildCSV(
            entries: entries,
            projectNames: ["p1": "project one", "p2": "project two"],
            now: Date()
        )

        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasPrefix("project one,"))
        XCTAssertTrue(lines[2].hasPrefix("project two,"))
    }

    func testExportUnknownProject() {
        let entry = TimeEntry(
            projectId: "unknown-id",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 10)
        )

        let csv = CSVExporter.buildCSV(
            entries: [entry],
            projectNames: [:],
            now: Date()
        )

        let lines = csv.split(separator: "\n")
        XCTAssertTrue(lines[1].hasPrefix("unknown,"))
    }

    func testExportWithCompletedEntry() {
        let start = Date.from(year: 2024, month: 1, day: 1, hour: 9)
        let end = Date.from(year: 2024, month: 1, day: 1, hour: 11)

        let entry = TimeEntry(
            projectId: "p1",
            start: start,
            end: end,
            note: nil
        )

        let csv = CSVExporter.buildCSV(
            entries: [entry],
            projectNames: ["p1": "test"],
            now: Date()
        )

        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains(",7200,"))
    }

    // MARK: - CSV Escaping

    func testExportEscapesNewlines() {
        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 10),
            note: "line1\nline2"
        )

        let csv = CSVExporter.buildCSV(
            entries: [entry],
            projectNames: ["p1": "test"],
            now: Date()
        )

        XCTAssertTrue(csv.contains("\"line1\nline2\""))
    }

    func testExportEscapesCommas() {
        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 10),
            note: "one, two, three"
        )

        let csv = CSVExporter.buildCSV(
            entries: [entry],
            projectNames: ["p1": "test"],
            now: Date()
        )

        XCTAssertTrue(csv.contains("\"one, two, three\""))
    }

    func testExportNoEscapingForSimpleText() {
        let entry = TimeEntry(
            projectId: "p1",
            start: Date.from(year: 2024, month: 1, day: 1, hour: 9),
            end: Date.from(year: 2024, month: 1, day: 1, hour: 10),
            note: "simple note"
        )

        let csv = CSVExporter.buildCSV(
            entries: [entry],
            projectNames: ["p1": "test"],
            now: Date()
        )

        XCTAssertTrue(csv.contains(",simple note\n"))
    }
}
