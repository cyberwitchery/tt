import Foundation
import Combine

@MainActor
final class AppState: ObservableObject, TimeTrackerDelegate {
    static let shared = AppState()

    private let tracker: TimeTracker
    private var timer: Timer?

    @Published private(set) var projects: [Project] = []
    @Published private(set) var runningEntry: TimeEntry?
    @Published private(set) var todaysEntries: [TimeEntry] = []
    @Published private(set) var dailyTotals: [ProjectTotal] = []
    @Published private(set) var weeklyTotals: [DayTotal] = []
    @Published var selectedProjectId: String?
    @Published var elapsedSeconds: Int = 0

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
        selectedProjectId = tracker.selectedProjectId
        updateElapsed()
    }

    func loadInitialState() async {
        do {
            try tracker.loadInitialState()
            syncFromTracker()
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
        do {
            try tracker.startTimer()
            syncFromTracker()
            restartTimerIfNeeded()
        } catch {
            return
        }
    }

    func stopTimer() {
        do {
            try tracker.stopTimer()
            syncFromTracker()
            stopTimerUpdates()
            elapsedSeconds = 0
        } catch {
            return
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
            return
        }
    }

    func archiveProject(id: String) {
        do {
            try tracker.archiveProject(id: id)
            syncFromTracker()
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
        elapsedSeconds = tracker.elapsedSeconds()
    }

    func refreshTodaysEntries() {
        tracker.refreshTodaysEntries()
        syncFromTracker()
    }

    func updateEntry(id: String, start: Date, end: Date?, note: String?) {
        do {
            try tracker.updateEntry(id: id, start: start, end: end, note: note)
            syncFromTracker()
            restartTimerIfNeeded()
        } catch {
            return
        }
    }

    func deleteEntry(id: String) {
        do {
            try tracker.deleteEntry(id: id)
            syncFromTracker()
            restartTimerIfNeeded()
        } catch {
            return
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

    func exportCSV(range: Range<Date>, to url: URL, now: Date = Date()) throws {
        try tracker.exportCSV(range: range, to: url, now: now)
    }
}

extension Notification.Name {
    static let ttShowMainWindow = Notification.Name("tt.showMainWindow")
    static let ttHidePanel = Notification.Name("tt.hidePanel")
    static let ttRequestQuit = Notification.Name("tt.requestQuit")
}
