import XCTest
@testable import tt

final class CSVExporterTests: XCTestCase {
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
}
