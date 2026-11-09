import Foundation
import Combine
import GRDB

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState(database: DatabaseManager.shared)

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
    var projectTotalsForSelectedDay: [ProjectTotal] { tracker.projectTotalsForSelectedDay }
    var startedAt: Date? { tracker.startedAt }
    var idleSeconds: Int? { tracker.idleSeconds() }
    var selectedProjectId: String? { tracker.selectedProjectId }
    var elapsedSeconds: Int { tracker.elapsedSeconds() }
    @Published private(set) var lastError: String?
    private var errorDismissTask: Task<Void, Never>?

    init(database: Result<DatabaseManager, Error>, days: DayCalendar = DayCalendar()) {
        let dbQueue: DatabaseQueue
        var dbError: Error?

        do {
            dbQueue = try database.get().dbQueue
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
            timeEntryRepository: timeEntryRepository,
            days: days
        )
        observeTracker()

        if let dbError {
            surfaceError(dbError)
        }
        loadInitialState()
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

    func recentDayTotals() -> [DayTotal] {
        tracker.recentDayTotals()
    }

    func projectAllTimeSeconds(for projectId: String) -> Int {
        tracker.projectAllTimeSeconds(for: projectId)
    }

    func loadInitialState() {
        defer { restartTimerIfNeeded(); startIdleTimer() }
        do {
            try tracker.loadInitialState()
        } catch {
            surfaceError(error)
        }
    }

    func startTimer() {
        defer { restartTimerIfNeeded() }
        do {
            try tracker.startTimer()
        } catch {
            surfaceError(error)
        }
    }

    func stopTimer() {
        defer { restartTimerIfNeeded() }
        do {
            try tracker.stopTimer()
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
        perform { _ = try tracker.rollOverIfNeeded() }
        objectWillChange.send()
    }

    func refreshEntries() {
        perform { try tracker.refreshEntries() }
    }

    func stepDay(by days: Int) {
        perform { try tracker.stepDay(by: days) }
    }

    func showToday() {
        perform { try tracker.goToToday() }
    }

    func updateEntry(id: String, start: Date, end: Date?, note: String?, projectId: String? = nil) {
        defer { restartTimerIfNeeded() }
        do {
            try tracker.updateEntry(id: id, start: start, end: end, note: note, projectId: projectId)
        } catch {
            surfaceError(error)
        }
    }

    func deleteEntry(id: String) {
        defer { restartTimerIfNeeded() }
        do {
            try tracker.deleteEntry(id: id)
        } catch {
            surfaceError(error)
        }
    }

    func refreshProjects() {
        perform { try tracker.refreshProjects() }
    }

    func projectName(for projectId: String) -> String {
        tracker.projectName(for: projectId)
    }

    func refreshReports() {
        perform { try tracker.refreshReports() }
    }

    func exportCSV(range: Range<Date>, to url: URL) {
        do {
            try tracker.exportCSV(range: range, to: url)
        } catch {
            surfaceError(error)
        }
    }

    func recentTotalSeconds() -> Int { tracker.recentTotalSeconds() }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { surfaceError(error) }
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
