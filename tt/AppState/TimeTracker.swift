import Foundation
import Combine

final class TimeTracker: ObservableObject {
    private let projectRepository: ProjectRepository
    private let timeEntryRepository: TimeEntryRepository
    let days: DayCalendar

    @Published private(set) var projects: [Project] = []
    private var allProjectNames: [String: String] = [:]
    @Published private(set) var runningEntry: TimeEntry?
    @Published private(set) var todaysEntries: [TimeEntry] = []
    @Published private(set) var visibleEntries: [TimeEntry] = []
    /// days back from today. 0 is today.
    @Published private(set) var dayOffset: Int = 0
    @Published private(set) var projectTotalsForSelectedDay: [ProjectTotal] = []
    private var weekEntries: [TimeEntry] = []
    @Published private(set) var projectCompletedTotals: [String: Int] = [:]
    @Published private(set) var lastEntryEnd: Date?
    /// the "today" the loaded entry list was fetched against.
    private var loadedDay: DayCalendar.Day?
    @Published var selectedProjectId: String?

    var startedAt: Date? { runningEntry?.start }

    func idleSeconds() -> Int? {
        guard runningEntry == nil else { return nil }
        guard let last = lastEntryEnd else { return nil }
        return max(0, Int(days.now.timeIntervalSince(last).rounded(.down)))
    }

    /// the day the entry list and `projectTotalsForSelectedDay` describe.
    func selectedDay() -> Date {
        selectedDay(at: days.now).start
    }

    private func selectedDay(at now: Date) -> DayCalendar.Day {
        days.day(byAdding: dayOffset, to: days.day(containing: now))
    }

    var isViewingToday: Bool { dayOffset == 0 }

    /// step the selection by `days`, never past today.
    func stepDay(by offset: Int) throws {
        let target = min(0, dayOffset + offset)
        guard target != dayOffset else { return }
        try browse(to: target)
    }

    func goToToday() throws {
        guard dayOffset != 0 else { return }
        try browse(to: 0)
    }

    private func browse(to offset: Int) throws {
        let previous = dayOffset
        dayOffset = offset
        do { try reload(at: days.now) }
        catch { dayOffset = previous; throw error }
    }

    /// seconds tracked on the selected day, clipped to it.
    func visibleDayTotalSeconds() -> Int {
        let now = days.now
        return ReportBuilder.dayTotalSeconds(
            entries: visibleEntries,
            day: selectedDay(at: now),
            now: now
        )
    }

    /// seconds tracked today, whichever day is selected.
    func todayTotalSeconds() -> Int {
        let now = days.now
        return ReportBuilder.dayTotalSeconds(entries: todaysEntries, day: days.day(containing: now), now: now)
    }

    /// seconds tracked on each of the seven days ending on `now`'s day.
    func recentDayTotals() -> [DayTotal] {
        let now = days.now
        return ReportBuilder.dayTotals(
            entries: weekEntries,
            week: days.week(endingOn: now),
            now: now
        )
    }

    func recentTotalSeconds() -> Int {
        recentDayTotals().reduce(0) { $0 + $1.seconds }
    }

    /// reload when `now` has crossed midnight since the last fetch, holding a
    /// browsed day on its own date. true if it reloaded.
    @discardableResult
    func rollOverIfNeeded() throws -> Bool {
        guard let loadedDay else { return false }
        let now = days.now
        let today = days.day(containing: now)
        guard today != loadedDay else { return false }

        if !isViewingToday {
            let crossed = days.daysBetween(loadedDay, and: today)
            dayOffset = min(0, dayOffset - crossed)
        }
        try reload(at: now)
        return true
    }

    init(
        projectRepository: ProjectRepository,
        timeEntryRepository: TimeEntryRepository,
        days: DayCalendar = DayCalendar()
    ) {
        self.projectRepository = projectRepository
        self.timeEntryRepository = timeEntryRepository
        self.days = days
    }

    // MARK: - Initial Load

    func loadInitialState() throws {
        try timeEntryRepository.resolveMultipleRunningEntries()
        let defaultProject = try projectRepository.ensureDefaultProject()
        try loadProjects()
        selectedProjectId = defaultProject.id
        runningEntry = try timeEntryRepository.fetchRunning()
        dayOffset = 0
        let now = days.now
        loadedDay = days.day(containing: now)
        todaysEntries = try timeEntryRepository.fetchEntries(on: days.day(containing: now))
        visibleEntries = todaysEntries
        try refreshReports(at: now)
    }

    // MARK: - Timer Control

    func startTimer() throws {
        guard runningEntry == nil else { return }
        guard let projectId = selectedProjectId else { return }

        let now = days.now
        let entry = TimeEntry(projectId: projectId, start: now)
        try timeEntryRepository.insertRunning(entry: entry)
        runningEntry = entry
        dayOffset = 0
        try reload(at: now)
    }

    func stopTimer() throws {
        guard let entry = runningEntry else { return }
        let now = days.now
        _ = try timeEntryRepository.stopRunning(entry: entry, end: now)
        runningEntry = nil
        dayOffset = 0
        try reload(at: now)
    }

    var isRunning: Bool {
        runningEntry != nil
    }

    func elapsedSeconds() -> Int {
        guard let entry = runningEntry else { return 0 }
        return TimeMath.durationSeconds(start: entry.start, end: entry.end, now: days.now)
    }

    // MARK: - Project Management

    func selectProject(id: String) {
        selectedProjectId = id
    }

    @discardableResult
    func createProject(name: String) throws -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let project = Project(name: trimmed.lowercased())
        try projectRepository.insert(project)
        try refreshProjects()
        return project
    }

    func archiveProject(id: String) throws {
        try projectRepository.archive(projectId: id)
        try refreshProjects()
    }

    func projectName(for projectId: String) -> String {
        allProjectNames[projectId] ?? "unknown"
    }

    // MARK: - Entry Management

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
        runningEntry = try timeEntryRepository.fetchRunning()
        try reload(at: days.now)
    }

    func deleteEntry(id: String) throws {
        try timeEntryRepository.delete(id: id)
        runningEntry = try timeEntryRepository.fetchRunning()
        try reload(at: days.now)
    }

    // MARK: - Refresh

    func refreshProjects() throws {
        try loadProjects()
        if !projects.contains(where: { $0.id == selectedProjectId }) {
            selectedProjectId = projects.first?.id
        }
        try refreshReports()
    }

    private func loadProjects() throws {
        let active = try projectRepository.fetchAllActive()
        let all = try projectRepository.fetchAll()
        projects = active
        allProjectNames = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.name) })
    }

    func refreshEntries() throws {
        try refreshEntries(at: days.now)
    }

    private func refreshEntries(at now: Date) throws {
        let today = try timeEntryRepository.fetchEntries(on: days.day(containing: now))
        let visible = isViewingToday ? today : try timeEntryRepository.fetchEntries(on: selectedDay(at: now))
        loadedDay = days.day(containing: now)
        todaysEntries = today
        visibleEntries = visible
    }

    func refreshReports() throws {
        try refreshReports(at: days.now)
    }

    private func reload(at now: Date) throws {
        try refreshEntries(at: now)
        try refreshReports(at: now)
    }

    private func refreshReports(at now: Date) throws {
        let day = selectedDay(at: now).range
        let dailyEntries = try timeEntryRepository.fetchEntries(in: day)
        let recentEntries = try timeEntryRepository.fetchEntries(in: days.week(endingOn: now).range)
        let completed = try timeEntryRepository.fetchCompletedTotalsByProject()
        let last = try timeEntryRepository.fetchMostRecentlyEnded()?.end
        projectTotalsForSelectedDay = ReportBuilder.projectTotals(
            entries: dailyEntries, rangeStart: day.lowerBound, rangeEnd: day.upperBound, now: now,
            projectNameForId: { self.projectName(for: $0) }
        )
        weekEntries = recentEntries
        projectCompletedTotals = completed
        lastEntryEnd = last
    }

    func projectAllTimeSeconds(for projectId: String) -> Int {
        var seconds = projectCompletedTotals[projectId] ?? 0
        if let entry = runningEntry, entry.projectId == projectId {
            seconds += TimeMath.durationSeconds(start: entry.start, end: entry.end, now: days.now)
        }
        return seconds
    }

    // MARK: - Export

    func exportCSV(range: Range<Date>, to url: URL) throws {
        let entries = try timeEntryRepository.fetchEntries(in: range)
        let allProjects = try projectRepository.fetchAll()
        let projectNames = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.id, $0.name) })

        let output = CSVExporter.buildCSV(entries: entries, projectNames: projectNames, now: days.now)
        try output.write(to: url, atomically: true, encoding: .utf8)
    }
}
