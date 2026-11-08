import Foundation
import Combine
import GRDB

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private let tracker: TimeTracker
    var days: DayCalendar { tracker.days }
    private var timer: Timer?
    private var idleTimer: Timer?

    private var trackerObservation: AnyCancellable?
    var projects: [Project] { tracker.projects }
    var runningEntry: TimeEntry? { tracker.runningEntry }
    var todaysEntries: [TimeEntry] { tracker.todaysEntries }
    var visibleEntries: [TimeEntry] { tracker.visibleEntries }
    var selectedDay: Date { tracker.selectedDay() }
    var isViewingToday: Bool { tracker.isViewingToday }
    var dailyTotals: [ProjectTotal] { tracker.dailyTotals }
    var startedAt: Date? { tracker.startedAt }
    var idleSeconds: Int? { tracker.idleSeconds() }
    var selectedProjectId: String? { tracker.selectedProjectId }
    var elapsedSeconds: Int { tracker.elapsedSeconds() }
    @Published private(set) var lastError: String?
    private var errorDismissTask: Task<Void, Never>?

    private init() {
        let dbQueue: DatabaseQueue
        var dbError: Error?

        do {
            dbQueue = try DatabaseManager.shared.get().dbQueue
        } catch {
            dbError = error
            // in-memory fallback so the UI still renders (data won't persist).
            // loadInitialState will fail on missing tables — that error is
            // caught and surfaced through lastError.
            dbQueue = try! DatabaseQueue()
        }

        let projectRepository = ProjectRepository(dbQueue: dbQueue)
        let timeEntryRepository = TimeEntryRepository(dbQueue: dbQueue)
        self.tracker = TimeTracker(
            projectRepository: projectRepository,
            timeEntryRepository: timeEntryRepository
        )
        observeTracker()

        Task {
            if let dbError {
                self.surfaceError(dbError)
            }
            self.loadInitialState()
        }
    }

    // for testing only
    init(tracker: TimeTracker) {
        self.tracker = tracker
        observeTracker()
    }

    private func observeTracker() {
        trackerObservation = tracker.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func visibleDayTotalSeconds() -> Int {
        tracker.visibleDayTotalSeconds()
    }

    func todayTotalSeconds() -> Int {
        tracker.todayTotalSeconds()
    }

    func weeklyTotals() -> [DayTotal] {
        tracker.weeklyTotals()
    }

    func projectAllTimeSeconds(for projectId: String) -> Int {
        tracker.projectAllTimeSeconds(for: projectId)
    }

    func loadInitialState() {
        do {
            try tracker.loadInitialState()
            restartTimerIfNeeded()
            startIdleTimer()
        } catch {
            surfaceError(error)
        }
    }

    func startTimer() {
        do {
            try tracker.startTimer()
            restartTimerIfNeeded()
        } catch {
            surfaceError(error)
        }
    }

    func stopTimer() {
        do {
            try tracker.stopTimer()
            stopTimerUpdates()
        } catch {
            surfaceError(error)
        }
    }

    func selectProject(id: String) {
        tracker.selectProject(id: id)
    }

    func createProject(name: String) {
        do {
            try tracker.createProject(name: name)
        } catch {
            surfaceError(error)
        }
    }

    func archiveProject(id: String) {
        do {
            try tracker.archiveProject(id: id)
        } catch {
            surfaceError(error)
        }
    }

    private func restartTimerIfNeeded() {
        stopTimerUpdates()
        guard runningEntry != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
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
                self?.tick()
            }
        }
    }

    /// Refresh derived clock values and reload after a day boundary.
    func tick() {
        tracker.rollOverIfNeeded()
        objectWillChange.send()
    }

    func refreshEntries() {
        tracker.refreshEntries()
    }

    func stepDay(by days: Int) {
        tracker.stepDay(by: days)
    }

    func showToday() {
        tracker.goToToday()
    }

    func updateEntry(id: String, start: Date, end: Date?, note: String?, projectId: String? = nil) {
        do {
            try tracker.updateEntry(id: id, start: start, end: end, note: note, projectId: projectId)
            restartTimerIfNeeded()
        } catch {
            surfaceError(error)
        }
    }

    func deleteEntry(id: String) {
        do {
            try tracker.deleteEntry(id: id)
            restartTimerIfNeeded()
        } catch {
            surfaceError(error)
        }
    }

    func refreshProjects(keepSelection: Bool) {
        tracker.refreshProjects(keepSelection: keepSelection)
    }

    func projectName(for projectId: String) -> String {
        tracker.projectName(for: projectId)
    }

    func refreshReports() {
        tracker.refreshReports()
    }

    func exportCSV(range: Range<Date>, to url: URL) {
        do {
            try tracker.exportCSV(range: range, to: url)
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
