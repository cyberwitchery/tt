import Foundation
import Combine

@MainActor
final class AppState: ObservableObject, TimeTrackerDelegate {
    static let shared = AppState()

    private let tracker: TimeTracker
    private var timer: Timer?
    private var idleTimer: Timer?

    @Published private(set) var projects: [Project] = []
    @Published private(set) var runningEntry: TimeEntry?
    @Published private(set) var todaysEntries: [TimeEntry] = []
    @Published private(set) var dailyTotals: [ProjectTotal] = []
    @Published private(set) var weeklyTotals: [DayTotal] = []
    @Published private(set) var projectCompletedTotals: [String: Int] = [:]
    @Published private(set) var startedAt: Date?
    @Published private(set) var idleSeconds: Int?
    @Published var selectedProjectId: String?
    @Published var elapsedSeconds: Int = 0
    @Published private(set) var lastError: String?
    private var errorDismissTask: Task<Void, Never>?

    private init() {
        let projectRepository = ProjectRepository()
        let timeEntryRepository = TimeEntryRepository()
        self.tracker = TimeTracker(
            projectRepository: projectRepository,
            timeEntryRepository: timeEntryRepository
        )
        tracker.delegate = self
        Task { await loadInitialState() }
    }

    // For testing only
    init(tracker: TimeTracker) {
        self.tracker = tracker
        tracker.delegate = self
    }

    nonisolated func timeTrackerDidUpdate() {
        Task { @MainActor in
            syncFromTracker()
        }
    }

    private func syncFromTracker() {
        projects = tracker.projects
        runningEntry = tracker.runningEntry
        todaysEntries = tracker.todaysEntries
        dailyTotals = tracker.dailyTotals
        weeklyTotals = tracker.weeklyTotals
        projectCompletedTotals = tracker.projectCompletedTotals
        startedAt = tracker.startedAt
        selectedProjectId = tracker.selectedProjectId
        updateElapsed()
        updateIdle()
    }

    private func updateIdle() {
        idleSeconds = tracker.idleSeconds()
    }

    func projectAllTimeSeconds(for projectId: String) -> Int {
        var seconds = projectCompletedTotals[projectId] ?? 0
        if runningEntry?.projectId == projectId {
            seconds += elapsedSeconds
        }
        return seconds
    }

    func loadInitialState() async {
        do {
            try tracker.loadInitialState()
            syncFromTracker()
            restartTimerIfNeeded()
            startIdleTimer()
        } catch {
            projects = []
            runningEntry = nil
            todaysEntries = []
            dailyTotals = []
            weeklyTotals = []
            projectCompletedTotals = [:]
            startedAt = nil
            idleSeconds = nil
            surfaceError(error)
        }
    }

    func startTimer() {
        do {
            try tracker.startTimer()
            syncFromTracker()
            restartTimerIfNeeded()
        } catch {
            surfaceError(error)
        }
    }

    func stopTimer() {
        do {
            try tracker.stopTimer()
            syncFromTracker()
            stopTimerUpdates()
            elapsedSeconds = 0
        } catch {
            surfaceError(error)
        }
    }

    func selectProject(id: String) {
        tracker.selectProject(id: id)
        selectedProjectId = id
    }

    func createProject(name: String) {
        do {
            try tracker.createProject(name: name)
            syncFromTracker()
        } catch {
            surfaceError(error)
        }
    }

    func archiveProject(id: String) {
        do {
            try tracker.archiveProject(id: id)
            syncFromTracker()
        } catch {
            surfaceError(error)
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

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateIdle()
            }
        }
    }

    private func updateElapsed() {
        elapsedSeconds = tracker.elapsedSeconds()
    }

    func refreshTodaysEntries() {
        tracker.refreshTodaysEntries()
        syncFromTracker()
    }

    func updateEntry(id: String, start: Date, end: Date?, note: String?, projectId: String? = nil) {
        do {
            try tracker.updateEntry(id: id, start: start, end: end, note: note, projectId: projectId)
            syncFromTracker()
            restartTimerIfNeeded()
        } catch {
            surfaceError(error)
        }
    }

    func deleteEntry(id: String) {
        do {
            try tracker.deleteEntry(id: id)
            syncFromTracker()
            restartTimerIfNeeded()
        } catch {
            surfaceError(error)
        }
    }

    func refreshProjects(keepSelection: Bool) {
        tracker.refreshProjects(keepSelection: keepSelection)
        syncFromTracker()
    }

    func projectName(for projectId: String) -> String {
        tracker.projectName(for: projectId)
    }

    func refreshReports(now: Date = Date(), calendar: Calendar = .current) {
        tracker.refreshReports(now: now, calendar: calendar)
        syncFromTracker()
    }

    func exportCSV(range: Range<Date>, to url: URL, now: Date = Date()) {
        do {
            try tracker.exportCSV(range: range, to: url, now: now)
        } catch {
            surfaceError(error)
        }
    }

    func dismissError() {
        errorDismissTask?.cancel()
        errorDismissTask = nil
        lastError = nil
    }

    private func surfaceError(_ error: Error) {
        lastError = error.localizedDescription
        errorDismissTask?.cancel()
        errorDismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            lastError = nil
        }
    }
}

extension Notification.Name {
    static let ttShowMainWindow = Notification.Name("tt.showMainWindow")
    static let ttHidePanel = Notification.Name("tt.hidePanel")
    static let ttRequestQuit = Notification.Name("tt.requestQuit")
}
