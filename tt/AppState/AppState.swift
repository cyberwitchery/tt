import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var projects: [Project] = []
    @Published private(set) var runningEntry: TimeEntry?
    @Published private(set) var todaysEntries: [TimeEntry] = []
    @Published private(set) var dailyTotals: [ProjectTotal] = []
    @Published private(set) var weeklyTotals: [DayTotal] = []
    @Published var selectedProjectId: String?
    @Published var elapsedSeconds: Int = 0

    private let projectRepository = ProjectRepository()
    private let timeEntryRepository = TimeEntryRepository()
    private var timer: Timer?

    private init() {
        Task { await loadInitialState() }
    }

    func loadInitialState() async {
        do {
            try timeEntryRepository.resolveMultipleRunningEntries()
            let defaultProject = try projectRepository.ensureDefaultProject()
            projects = try projectRepository.fetchAllActive()
            selectedProjectId = defaultProject.id
            runningEntry = try timeEntryRepository.fetchRunning()
            todaysEntries = try timeEntryRepository.fetchEntriesForToday()
            refreshReports()
            updateElapsed()
            restartTimerIfNeeded()
        } catch {
            projects = []
            runningEntry = nil
            todaysEntries = []
            dailyTotals = []
            weeklyTotals = []
        }
    }

    func startTimer() {
        guard runningEntry == nil else { return }
        guard let projectId = selectedProjectId else { return }

        let entry = TimeEntry(projectId: projectId, start: Date())
        do {
            try timeEntryRepository.insertRunning(entry: entry)
            runningEntry = entry
            refreshTodaysEntries()
            refreshReports()
            restartTimerIfNeeded()
        } catch {
            return
        }
    }

    func stopTimer() {
        guard let entry = runningEntry else { return }
        do {
            _ = try timeEntryRepository.stopRunning(entry: entry, end: Date())
            runningEntry = nil
            stopTimerUpdates()
            elapsedSeconds = 0
            refreshTodaysEntries()
            refreshReports()
        } catch {
            return
        }
    }

    func selectProject(id: String) {
        selectedProjectId = id
    }

    func createProject(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try projectRepository.insert(Project(name: trimmed.lowercased()))
            refreshProjects(keepSelection: true)
        } catch {
            return
        }
    }

    func archiveProject(id: String) {
        do {
            try projectRepository.archive(projectId: id)
            refreshProjects(keepSelection: false)
        } catch {
            return
        }
    }

    private func restartTimerIfNeeded() {
        stopTimerUpdates()
        guard runningEntry != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
    }

    private func stopTimerUpdates() {
        timer?.invalidate()
        timer = nil
    }

    private func updateElapsed() {
        guard let entry = runningEntry else {
            elapsedSeconds = 0
            return
        }
        elapsedSeconds = TimeMath.durationSeconds(start: entry.start, end: entry.end)
    }

    func refreshTodaysEntries() {
        do {
            todaysEntries = try timeEntryRepository.fetchEntriesForToday()
        } catch {
            todaysEntries = []
        }
    }

    func updateEntry(id: String, start: Date, end: Date?, note: String?) {
        let sanitizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEnd = end.map { max($0, start) }

        do {
            guard var entry = todaysEntries.first(where: { $0.id == id }) else { return }
            entry.start = start
            entry.end = normalizedEnd
            entry.note = sanitizedNote?.isEmpty == true ? nil : sanitizedNote
            try timeEntryRepository.update(entry)
            try timeEntryRepository.resolveMultipleRunningEntries()
            runningEntry = try timeEntryRepository.fetchRunning()
            refreshTodaysEntries()
            refreshReports()
            updateElapsed()
            restartTimerIfNeeded()
        } catch {
            return
        }
    }

    func deleteEntry(id: String) {
        do {
            try timeEntryRepository.delete(id: id)
            runningEntry = try timeEntryRepository.fetchRunning()
            refreshTodaysEntries()
            refreshReports()
            updateElapsed()
            restartTimerIfNeeded()
        } catch {
            return
        }
    }

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

    func projectName(for projectId: String) -> String {
        projects.first(where: { $0.id == projectId })?.name.lowercased() ?? "unknown"
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
                projectNameForId: { projectName(for: $0) }
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

    func exportCSV(range: Range<Date>, to url: URL, now: Date = Date()) throws {
        let entries = try timeEntryRepository.fetchEntries(in: range)
        let projects = try projectRepository.fetchAll()
        let projectNames = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name.lowercased()) })

        let output = CSVExporter.buildCSV(entries: entries, projectNames: projectNames, now: now)
        try output.write(to: url, atomically: true, encoding: .utf8)
    }
}

extension Notification.Name {
    static let ttShowMainWindow = Notification.Name("tt.showMainWindow")
    static let ttHidePanel = Notification.Name("tt.hidePanel")
    static let ttRequestQuit = Notification.Name("tt.requestQuit")
}
