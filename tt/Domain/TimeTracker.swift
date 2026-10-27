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
    /// the "today" the loaded entry list was fetched against.
    private var loadedDay: Date?
    /// noon on that day's date, which a time-zone change can't move.
    private var loadedNoon: DateComponents?
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

    /// seconds tracked on the selected day, clipped to it.
    func visibleDayTotalSeconds(now: Date = Date(), calendar: Calendar = .current) -> Int {
        ReportBuilder.dayTotalSeconds(
            entries: visibleEntries,
            day: selectedDay(now: now, calendar: calendar),
            now: now,
            calendar: calendar
        )
    }

    /// seconds tracked today, whichever day is selected.
    func todayTotalSeconds(now: Date = Date(), calendar: Calendar = .current) -> Int {
        ReportBuilder.dayTotalSeconds(entries: todaysEntries, day: now, now: now, calendar: calendar)
    }

    /// reload when `now` has crossed midnight since the last fetch, holding a
    /// browsed day on its own date. true if it reloaded.
    @discardableResult
    func rollOverIfNeeded(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let loadedDay, let loadedNoon else { return false }
        let today = calendar.startOfDay(for: now)
        guard today != loadedDay else { return false }

        if !isViewingToday {
            let crossed = calendar.dateComponents([.day], from: loadedNoon, to: Self.noon(of: now, calendar)).day ?? 0
            dayOffset = min(0, dayOffset - crossed)
        }
        refreshEntries(now: now, calendar: calendar)
        refreshReports(now: now, calendar: calendar)
        return true
    }

    private static func noon(of date: Date, _ calendar: Calendar) -> DateComponents {
        var noon = calendar.dateComponents([.era, .year, .month, .day], from: date)
        noon.hour = 12
        return noon
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
        let now = Date()
        loadedDay = Calendar.current.startOfDay(for: now)
        loadedNoon = Self.noon(of: now, .current)
        todaysEntries = try timeEntryRepository.fetchEntries(onDay: now)
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
        loadedDay = calendar.startOfDay(for: now)
        loadedNoon = Self.noon(of: now, calendar)
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
            let sixDaysBack = calendar.date(byAdding: .day, value: -6, to: today.lowerBound) ?? today.lowerBound
            let week = TimeMath.dayRange(from: sixDaysBack, through: now, calendar: calendar)

            let dailyEntries = try timeEntryRepository.fetchEntries(in: day)
            let weeklyEntries = try timeEntryRepository.fetchEntries(in: week)

            dailyTotals = ReportBuilder.dailyTotals(
                entries: dailyEntries,
                rangeStart: day.lowerBound,
                rangeEnd: day.upperBound,
                now: now,
                projectNameForId: { self.projectName(for: $0) }
            )
            weeklyTotals = ReportBuilder.weeklyTotals(
                entries: weeklyEntries,
                weekStart: week.lowerBound,
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
