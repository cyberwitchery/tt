import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState(database: DatabaseManager.shared)

    private let tracker: TimeTracker?
    let days: DayCalendar
    let storageError: String?
    var isStorageAvailable: Bool { tracker != nil }
    private var timer: Timer?
    private var idleTimer: Timer?

    private var trackerObservation: AnyCancellable?
    var projects: [Project] { tracker?.projects ?? [] }
    var runningEntry: TimeEntry? { tracker?.runningEntry }
    var todaysEntries: [TimeEntry] { tracker?.todaysEntries ?? [] }
    var visibleEntries: [TimeEntry] { tracker?.visibleEntries ?? [] }
    var selectedDay: Date { tracker?.selectedDay() ?? days.today.start }
    var isViewingToday: Bool { tracker?.isViewingToday ?? true }
    var projectTotalsForSelectedDay: [ProjectTotal] { tracker?.projectTotalsForSelectedDay ?? [] }
    var startedAt: Date? { tracker?.startedAt }
    var idleSeconds: Int? { tracker?.idleSeconds() }
    var selectedProjectId: String? { tracker?.selectedProjectId }
    var elapsedSeconds: Int { tracker?.elapsedSeconds() ?? 0 }
    @Published private(set) var lastError: String?
    private var errorDismissTask: Task<Void, Never>?

    init(database: Result<DatabaseManager, Error>, days: DayCalendar = DayCalendar()) {
        self.days = days
        switch database {
        case .success(let manager):
            tracker = TimeTracker(projectRepository: ProjectRepository(dbQueue: manager.dbQueue),
                                  timeEntryRepository: TimeEntryRepository(dbQueue: manager.dbQueue), days: days)
            storageError = nil
        case .failure(let error):
            tracker = nil
            storageError = "Unable to open the tracking database: \(error.localizedDescription)"
        }
        observeTracker()
        if let storageError { lastError = storageError }
        else { loadInitialState() }
    }

    init(tracker: TimeTracker) {
        self.tracker = tracker
        days = tracker.days
        storageError = nil
        observeTracker()
    }

    private func observeTracker() {
        trackerObservation = tracker?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func visibleDayTotalSeconds() -> Int {
        tracker?.visibleDayTotalSeconds() ?? 0
    }

    func todayTotalSeconds() -> Int {
        tracker?.todayTotalSeconds() ?? 0
    }

    func recentDayTotals() -> [DayTotal] {
        tracker?.recentDayTotals() ?? []
    }

    func projectAllTimeSeconds(for projectId: String) -> Int {
        tracker?.projectAllTimeSeconds(for: projectId) ?? 0
    }

    func loadInitialState() {
        defer { restartTimerIfNeeded(); startIdleTimer() }
        do {
            try tracker?.loadInitialState()
        } catch {
            surfaceError(error)
        }
    }

    func startTimer() {
        defer { restartTimerIfNeeded() }
        do {
            try tracker?.startTimer()
        } catch {
            surfaceError(error)
        }
    }

    func stopTimer() {
        defer { restartTimerIfNeeded() }
        do {
            try tracker?.stopTimer()
        } catch {
            surfaceError(error)
        }
    }

    func selectProject(id: String) {
        tracker?.selectProject(id: id)
    }

    @discardableResult
    func createProject(name: String) -> Project? {
        do { return try tracker?.createProject(name: name) }
        catch { surfaceError(error); return nil }
    }

    func archiveProject(id: String) {
        do {
            try tracker?.archiveProject(id: id)
        } catch {
            surfaceError(error)
        }
    }

    private func restartTimerIfNeeded() {
        stopTimerUpdates()
        guard runningEntry != nil else { return }
        timer = Self.scheduleTimer(interval: 1) { [weak self] in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    static func scheduleTimer(interval: TimeInterval, onTick: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in onTick() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func stopTimerUpdates() {
        timer?.invalidate()
        timer = nil
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Self.scheduleTimer(interval: 60) { [weak self] in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Refresh derived clock values and reload after a day boundary.
    func tick() {
        perform { _ = try tracker?.rollOverIfNeeded() }
        objectWillChange.send()
    }

    func refreshEntries() {
        perform { try tracker?.refreshEntries() }
    }

    func stepDay(by days: Int) {
        perform { try tracker?.stepDay(by: days) }
    }

    func showToday() {
        perform { try tracker?.goToToday() }
    }

    func updateEntry(id: String, start: Date, end: Date?, note: String?, projectId: String? = nil) {
        defer { restartTimerIfNeeded() }
        do {
            try tracker?.updateEntry(id: id, start: start, end: end, note: note, projectId: projectId)
        } catch {
            surfaceError(error)
        }
    }

    func deleteEntry(id: String) {
        defer { restartTimerIfNeeded() }
        do {
            try tracker?.deleteEntry(id: id)
        } catch {
            surfaceError(error)
        }
    }

    func refreshProjects() {
        perform { try tracker?.refreshProjects() }
    }

    func projectName(for projectId: String) -> String {
        tracker?.projectName(for: projectId) ?? "unknown"
    }

    func refreshReports() {
        perform { try tracker?.refreshReports() }
    }

    func exportCSV(range: Range<Date>, to url: URL) {
        do {
            try tracker?.exportCSV(range: range, to: url)
        } catch {
            surfaceError(error)
        }
    }

    func recentTotalSeconds() -> Int { tracker?.recentTotalSeconds() ?? 0 }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { surfaceError(error) }
    }

    func dismissError() {
        guard storageError == nil else { return }
        errorDismissTask?.cancel()
        errorDismissTask = nil
        lastError = nil
    }

    private func surfaceError(_ error: Error) {
        guard storageError == nil else { lastError = storageError; return }
        lastError = error.localizedDescription
        errorDismissTask?.cancel()
        errorDismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            lastError = nil
        }
    }
}
