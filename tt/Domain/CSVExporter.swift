import Foundation

enum CSVExporter {
    static func buildCSV(
        entries: [TimeEntry],
        projectNames: [String: String],
        now: Date
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "project,start,end,duration_seconds,note"
        var lines = [header]

        for entry in entries {
            let name = projectNames[entry.projectId] ?? "unknown"
            let startText = formatter.string(from: entry.start)
            let endText = entry.end.map { formatter.string(from: $0) } ?? ""
            let duration = TimeMath.durationSeconds(start: entry.start, end: entry.end, now: now)
            let note = entry.note ?? ""

            let row = [
                escapeCSV(name),
                escapeCSV(startText),
                escapeCSV(endText),
                String(duration),
                escapeCSV(note)
            ].joined(separator: ",")
            lines.append(row)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains("\"") || value.contains(",") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
