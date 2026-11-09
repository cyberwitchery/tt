import Foundation
import Combine

final class TimeTracker: ObservableObject {
    private let projectRepository: ProjectRepository
    private let timeEntryRepository: TimeEntryRepository
    let days: DayCalendar

    @Published private(set) var projects: [Project] = []
    private var allProjectNames: [String: String] = [:]
    private struct LoadedDay {
        let today: DayCalendar.Day
        let selection: DayCalendar.Day
        let offset: Int
    }

    private struct TrackingState {
        var runningEntry: TimeEntry?
        var loaded: LoadedDay?
        var entries: [TimeEntry] = []
        var completedTotals: [String: Int] = [:]
        var lastEntryEnd: Date?
    }

    @Published private var state = TrackingState()
    private var loaded: LoadedDay? { state.loaded }
    var runningEntry: TimeEntry? { state.runningEntry }
    var todaysEntries: [TimeEntry] { cachedEntries(in: days.today.range) }
    var visibleEntries: [TimeEntry] { cachedEntries(in: loaded?.selection.range ?? days.today.range) }

    private func cachedEntries(in range: Range<Date>) -> [TimeEntry] {
        state.entries.filter { $0.start < range.upperBound && ($0.end.map { $0 > range.lowerBound } ?? true) }
    }
    /// Offset from the day of the last successful load, committed with its entries.
    var dayOffset: Int { loaded?.offset ?? 0 }
    var projectTotalsForSelectedDay: [ProjectTotal] {
        let selection = loaded?.selection ?? days.today
        return ReportBuilder.projectTotals(entries: visibleEntries, rangeStart: selection.start,
                                           rangeEnd: selection.end, now: days.now,
                                           projectNameForId: { self.projectName(for: $0) })
    }
    var projectCompletedTotals: [String: Int] { state.completedTotals }
    var lastEntryEnd: Date? { state.lastEntryEnd }
    @Published var selectedProjectId: String?

    var startedAt: Date? { runningEntry?.start }

    func idleSeconds() -> Int? {
        guard runningEntry == nil else { return nil }
        guard let last = lastEntryEnd else { return nil }
        return max(0, Int(days.now.timeIntervalSince(last).rounded(.down)))
    }

    /// the day the entry list and `projectTotalsForSelectedDay` describe.
    func selectedDay() -> Date {
        loaded?.selection.start ?? days.today.start
    }

    private func offsetForReload(at now: Date) -> Int {
        guard let loaded, loaded.offset != 0 else { return 0 }
        return min(0, loaded.offset - days.daysBetween(loaded.today, and: days.day(containing: now)))
    }

    var isViewingToday: Bool { selectedDay() == days.today.start }

    /// step the selection by `days`, never past today.
    func stepDay(by offset: Int) throws {
        let now = days.now
        let target = min(0, offsetForReload(at: now) + offset)
        guard target != dayOffset || loaded?.today != days.day(containing: now) else { return }
        try reload(at: now, offset: target)
    }

    func goToToday() throws {
        guard !isViewingToday else { return }
        try reload(at: days.now, offset: 0)
    }

    /// seconds tracked on the selected day, clipped to it.
    func visibleDayTotalSeconds() -> Int {
        let now = days.now
        return ReportBuilder.dayTotalSeconds(
            entries: visibleEntries,
            day: loaded?.selection ?? days.day(containing: now),
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
            entries: state.entries,
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
        guard let loaded else { return false }
        let now = days.now
        guard days.day(containing: now) != loaded.today else { return false }
        try reload(at: now, offset: offsetForReload(at: now))
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
        state.runningEntry = try timeEntryRepository.fetchRunning()
        try reload(at: days.now, offset: 0)
    }

    // MARK: - Timer Control

    func startTimer() throws {
        guard runningEntry == nil else { return }
        guard let projectId = selectedProjectId else { return }

        let now = days.now
        let entry = try timeEntryRepository.insertRunning(entry: TimeEntry(projectId: projectId, start: now))
        reflectCommitted(entry, replacing: nil)
        try reload(at: now, offset: 0)
    }

    func stopTimer() throws {
        guard let entry = runningEntry else { return }
        let now = days.now
        let stopped = try timeEntryRepository.stopRunning(entry: entry, end: now)
        reflectCommitted(stopped, replacing: entry)
        try reload(at: now, offset: 0)
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

    func createProject(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try projectRepository.insert(Project(name: trimmed.lowercased()))
        try refreshProjects()
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
        guard var entry = try timeEntryRepository.get(id: id) else { return }
        let previous = entry
        // An editor opened while running may still submit nil after the timer stopped.
        let normalizedEnd = (end ?? entry.end).map { max($0, start) }
        entry.start = start
        entry.end = normalizedEnd
        entry.note = sanitizedNote?.isEmpty == true ? nil : sanitizedNote
        if let projectId, projects.contains(where: { $0.id == projectId }) {
            entry.projectId = projectId
        }
        let saved = try timeEntryRepository.update(entry)
        reflectCommitted(saved, replacing: previous)
        try timeEntryRepository.resolveMultipleRunningEntries()
        state.runningEntry = try timeEntryRepository.fetchRunning()
        let now = days.now
        try reload(at: now, offset: offsetForReload(at: now))
    }

    func deleteEntry(id: String) throws {
        let previous = try timeEntryRepository.get(id: id)
        try timeEntryRepository.delete(id: id)
        reflectCommitted(nil, replacing: previous)
        state.runningEntry = try timeEntryRepository.fetchRunning()
        let now = days.now
        try reload(at: now, offset: offsetForReload(at: now))
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
        let now = days.now
        try reload(at: now, offset: offsetForReload(at: now))
    }

    func refreshReports() throws {
        let now = days.now
        try reload(at: now, offset: offsetForReload(at: now))
    }

    private func reload(at now: Date, offset: Int) throws {
        // Finish every read before publishing selection, entries or totals.
        let today = days.day(containing: now)
        let selection = days.day(byAdding: offset, to: today)
        let recentRange = days.week(endingOn: now).range
        let recent = try timeEntryRepository.fetchEntries(in: recentRange)
        let visible = recentRange.contains(selection.start) ? [] : try timeEntryRepository.fetchEntries(on: selection)
        var byId = Dictionary(uniqueKeysWithValues: recent.map { ($0.id, $0) })
        for entry in visible { byId[entry.id] = entry }
        let entries = byId.values.sorted { $0.start > $1.start }
        let completed = try timeEntryRepository.fetchCompletedTotalsByProject()
        let last = try timeEntryRepository.fetchMostRecentlyEnded()?.end
        state = TrackingState(runningEntry: runningEntry, loaded: LoadedDay(today: today, selection: selection, offset: offset),
                              entries: entries, completedTotals: completed, lastEntryEnd: last)
    }

    /// A successful write is authoritative even if a subsequent read fails.
    private func reflectCommitted(_ entry: TimeEntry?, replacing previous: TimeEntry?) {
        guard let id = entry?.id ?? previous?.id else { return }
        var next = state
        if let entry, entry.end == nil { next.runningEntry = entry }
        else if next.runningEntry?.id == id { next.runningEntry = nil }

        next.entries.removeAll { $0.id == id }
        if let entry { next.entries.append(entry) }
        next.entries.sort { $0.start > $1.start }
        if let previous, let end = previous.end {
            let duration = TimeMath.durationSeconds(start: previous.start, end: end)
            next.completedTotals[previous.projectId] = max(0, (next.completedTotals[previous.projectId] ?? 0) - duration)
        }
        if let entry, let end = entry.end {
            next.completedTotals[entry.projectId, default: 0] += TimeMath.durationSeconds(start: entry.start, end: end)
        }
        if let previousEnd = previous?.end, previousEnd == next.lastEntryEnd, entry?.end != previousEnd {
            // The next latest end is unknown until reads recover.
            next.lastEntryEnd = nil
        } else if let end = entry?.end {
            next.lastEntryEnd = max(next.lastEntryEnd ?? end, end)
        }
        state = next
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
