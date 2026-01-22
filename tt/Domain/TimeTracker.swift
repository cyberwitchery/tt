import Foundation

protocol TimeTrackerDelegate: AnyObject {
    func timeTrackerDidUpdate()
}

final class TimeTracker {
    private let projectRepository: ProjectRepository
    private let timeEntryRepository: TimeEntryRepository

    weak var delegate: TimeTrackerDelegate?

    private(set) var projects: [Project] = []
    private(set) var runningEntry: TimeEntry?
    private(set) var todaysEntries: [TimeEntry] = []
    private(set) var dailyTotals: [ProjectTotal] = []
    private(set) var weeklyTotals: [DayTotal] = []
    var selectedProjectId: String?

    init(
        projectRepository: ProjectRepository,
        timeEntryRepository: TimeEntryRepository
    ) {
        self.projectRepository = projectRepository
        self.timeEntryRepository = timeEntryRepository
    }

    // MARK: - Initial Load

    func loadInitialState() throws {
        try timeEntryRepository.resolveMultipleRunningEntries()
        let defaultProject = try projectRepository.ensureDefaultProject()
        projects = try projectRepository.fetchAllActive()
        selectedProjectId = defaultProject.id
        runningEntry = try timeEntryRepository.fetchRunning()
        todaysEntries = try timeEntryRepository.fetchEntriesForToday()
        refreshReports()
    }

    // MARK: - Timer Control

    func startTimer() throws {
        guard runningEntry == nil else { return }
        guard let projectId = selectedProjectId else { return }

        let entry = TimeEntry(projectId: projectId, start: Date())
        try timeEntryRepository.insertRunning(entry: entry)
        runningEntry = entry
        refreshTodaysEntries()
        refreshReports()
        delegate?.timeTrackerDidUpdate()
    }

    func stopTimer() throws {
        guard let entry = runningEntry else { return }
        _ = try timeEntryRepository.stopRunning(entry: entry, end: Date())
        runningEntry = nil
        refreshTodaysEntries()
        refreshReports()
        delegate?.timeTrackerDidUpdate()
    }

    var isRunning: Bool {
        runningEntry != nil
    }

    func elapsedSeconds(now: Date = Date()) -> Int {
        guard let entry = runningEntry else { return 0 }
        return TimeMath.durationSeconds(start: entry.start, end: entry.end, now: now)
    }

    // MARK: - Project Management

    func selectProject(id: String) {
        selectedProjectId = id
    }

    func createProject(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try projectRepository.insert(Project(name: trimmed.lowercased()))
        refreshProjects(keepSelection: true)
    }

    func archiveProject(id: String) throws {
        try projectRepository.archive(projectId: id)
        refreshProjects(keepSelection: false)
    }

    func projectName(for projectId: String) -> String {
        projects.first(where: { $0.id == projectId })?.name.lowercased() ?? "unknown"
    }

    // MARK: - Entry Management
    
    func getEntry(id: String) throws -> TimeEntry? {
        return try timeEntryRepository.get(id: id)
    }

    func updateEntry(id: String, start: Date, end: Date?, note: String?) throws {
        let sanitizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEnd = end.map { max($0, start) }

        guard var entry = try timeEntryRepository.get(id: id) else { return }
        entry.start = start
        entry.end = normalizedEnd
        entry.note = sanitizedNote?.isEmpty == true ? nil : sanitizedNote
        try timeEntryRepository.update(entry)
        try timeEntryRepository.resolveMultipleRunningEntries()
        runningEntry = try timeEntryRepository.fetchRunning()
        refreshTodaysEntries()
        refreshReports()
        delegate?.timeTrackerDidUpdate()
    }

    func deleteEntry(id: String) throws {
        try timeEntryRepository.delete(id: id)
        runningEntry = try timeEntryRepository.fetchRunning()
        refreshTodaysEntries()
        refreshReports()
        delegate?.timeTrackerDidUpdate()
    }

    // MARK: - Refresh

    func refreshProjects(keepSelection: Bool) {
        do {
            projects = try projectRepository.fetchAllActive()
            if keepSelection {
                return
            }
            if let selectedProjectId, projects.contains(where: { $0.id == selectedProjectId }) {
                return
            }
            selectedProjectId = projects.first?.id
        } catch {
            projects = []
        }
        refreshReports()
    }

    func refreshTodaysEntries() {
        do {
            todaysEntries = try timeEntryRepository.fetchEntriesForToday()
        } catch {
            todaysEntries = []
        }
    }

    func refreshReports(now: Date = Date(), calendar: Calendar = .current) {
        do {
            let startOfDay = calendar.startOfDay(for: now)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
            let weekStart = calendar.date(byAdding: .day, value: -6, to: startOfDay) ?? startOfDay
            let weekEnd = endOfDay

            let dailyEntries = try timeEntryRepository.fetchEntries(in: startOfDay..<endOfDay)
            let weeklyEntries = try timeEntryRepository.fetchEntries(in: weekStart..<weekEnd)

            dailyTotals = ReportBuilder.dailyTotals(
                entries: dailyEntries,
                rangeStart: startOfDay,
                rangeEnd: endOfDay,
                now: now,
                projectNameForId: { self.projectName(for: $0) }
            )
            weeklyTotals = ReportBuilder.weeklyTotals(
                entries: weeklyEntries,
                weekStart: weekStart,
                now: now,
                calendar: calendar
            )
        } catch {
            dailyTotals = []
            weeklyTotals = []
        }
    }

    // MARK: - Export

    func exportCSV(range: Range<Date>, to url: URL, now: Date = Date()) throws {
        let entries = try timeEntryRepository.fetchEntries(in: range)
        let allProjects = try projectRepository.fetchAll()
        let projectNames = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.id, $0.name.lowercased()) })

        let output = CSVExporter.buildCSV(entries: entries, projectNames: projectNames, now: now)
        try output.write(to: url, atomically: true, encoding: .utf8)
    }
}
