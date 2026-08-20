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
    private(set) var visibleEntries: [TimeEntry] = []
    /// days back from today. 0 is today.
    private(set) var dayOffset: Int = 0
    private(set) var dailyTotals: [ProjectTotal] = []
    private(set) var weeklyTotals: [DayTotal] = []
    private(set) var projectCompletedTotals: [String: Int] = [:]
    private(set) var lastEntryEnd: Date?
    var selectedProjectId: String?

    var startedAt: Date? { runningEntry?.start }

    func idleSeconds(now: Date = Date()) -> Int? {
        guard runningEntry == nil else { return nil }
        guard let last = lastEntryEnd else { return nil }
        return max(0, Int(now.timeIntervalSince(last).rounded(.down)))
    }

    /// the day the entry list and `dailyTotals` describe.
    func selectedDay(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        guard dayOffset != 0 else { return today }
        return calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
    }

    var isViewingToday: Bool { dayOffset == 0 }

    /// step the selection by `days`, never past today.
    func stepDay(by days: Int) {
        let target = min(0, dayOffset + days)
        guard target != dayOffset else { return }
        dayOffset = target
        refreshEntries()
        refreshReports()
    }

    func goToToday() {
        guard dayOffset != 0 else { return }
        dayOffset = 0
        refreshEntries()
        refreshReports()
    }

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
        dayOffset = 0
        todaysEntries = try timeEntryRepository.fetchEntries(onDay: Date())
        visibleEntries = todaysEntries
        refreshReports()
    }

    // MARK: - Timer Control

    func startTimer() throws {
        guard runningEntry == nil else { return }
        guard let projectId = selectedProjectId else { return }

        let entry = TimeEntry(projectId: projectId, start: Date())
        try timeEntryRepository.insertRunning(entry: entry)
        runningEntry = entry
        dayOffset = 0
        refreshEntries()
        refreshReports()
        delegate?.timeTrackerDidUpdate()
    }

    func stopTimer() throws {
        guard let entry = runningEntry else { return }
        _ = try timeEntryRepository.stopRunning(entry: entry, end: Date())
        runningEntry = nil
        dayOffset = 0
        refreshEntries()
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

    func updateEntry(id: String, start: Date, end: Date?, note: String?, projectId: String? = nil) throws {
        let sanitizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEnd = end.map { max($0, start) }

        guard var entry = try timeEntryRepository.get(id: id) else { return }
        entry.start = start
        entry.end = normalizedEnd
        entry.note = sanitizedNote?.isEmpty == true ? nil : sanitizedNote
        if let projectId, projects.contains(where: { $0.id == projectId }) {
            entry.projectId = projectId
        }
        try timeEntryRepository.update(entry)
        try timeEntryRepository.resolveMultipleRunningEntries()
        runningEntry = try timeEntryRepository.fetchRunning()
        refreshEntries()
        refreshReports()
        delegate?.timeTrackerDidUpdate()
    }

    func deleteEntry(id: String) throws {
        try timeEntryRepository.delete(id: id)
        runningEntry = try timeEntryRepository.fetchRunning()
        refreshEntries()
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

    func refreshEntries(now: Date = Date(), calendar: Calendar = .current) {
        do {
            todaysEntries = try timeEntryRepository.fetchEntries(onDay: now, calendar: calendar)
            if isViewingToday {
                visibleEntries = todaysEntries
            } else {
                let day = selectedDay(now: now, calendar: calendar)
                visibleEntries = try timeEntryRepository.fetchEntries(onDay: day, calendar: calendar)
            }
        } catch {
            todaysEntries = []
            visibleEntries = []
        }
    }

    func refreshReports(now: Date = Date(), calendar: Calendar = .current) {
        do {
            let today = TimeMath.dayRange(for: now, calendar: calendar)
            let day = TimeMath.dayRange(for: selectedDay(now: now, calendar: calendar), calendar: calendar)
            let weekStart = calendar.date(byAdding: .day, value: -6, to: today.lowerBound) ?? today.lowerBound
            let weekEnd = today.upperBound

            let dailyEntries = try timeEntryRepository.fetchEntries(in: day)
            let weeklyEntries = try timeEntryRepository.fetchEntries(in: weekStart..<weekEnd)

            dailyTotals = ReportBuilder.dailyTotals(
                entries: dailyEntries,
                rangeStart: day.lowerBound,
                rangeEnd: day.upperBound,
                now: now,
                projectNameForId: { self.projectName(for: $0) }
            )
            weeklyTotals = ReportBuilder.weeklyTotals(
                entries: weeklyEntries,
                weekStart: weekStart,
                now: now,
                calendar: calendar
            )
            projectCompletedTotals = (try? timeEntryRepository.fetchCompletedTotalsByProject()) ?? [:]
            lastEntryEnd = (try? timeEntryRepository.fetchMostRecentlyEnded())?.end
        } catch {
            dailyTotals = []
            weeklyTotals = []
            projectCompletedTotals = [:]
            lastEntryEnd = nil
        }
    }

    func projectAllTimeSeconds(for projectId: String, now: Date = Date()) -> Int {
        var seconds = projectCompletedTotals[projectId] ?? 0
        if let entry = runningEntry, entry.projectId == projectId {
            seconds += TimeMath.durationSeconds(start: entry.start, end: entry.end, now: now)
        }
        return seconds
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
