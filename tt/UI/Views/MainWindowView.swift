import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainWindowView: View {
    @ObservedObject var appState: AppState

    @State private var projectPickerOpen = false

    @State private var confirmingStop = false

    @State private var editSession: EntryEditSession

    @State private var addingProject = false
    @State private var newProjectName = ""
    @FocusState private var newProjectFocused: Bool
    @State private var confirmingArchiveId: String?

    @State private var exportStart: Date
    @State private var exportEnd: Date

    init(appState: AppState) {
        self.appState = appState
        _editSession = State(initialValue: EntryEditSession(days: appState.days))
        let now = appState.days.now
        _exportStart = State(initialValue: appState.days.monthStart(containing: now))
        _exportEnd = State(initialValue: now)
    }

    // keyboard flow: after user picks a project via the N shortcut, start timer.
    @State private var startAfterProjectPick = false

    // week day labels (localized short)
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EE"
        return f
    }()

    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EE dd.MM"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let errorMessage = appState.lastError {
                    errorBanner(errorMessage)
                        .padding(.top, 40)
                }
                headerRow
                    .padding(.top, appState.lastError == nil ? 40 : 10)
                    .zIndex(20) // header dropdown must float above later sections
                timerRow
                    .padding(.top, 14)
                BrutalistDivider()

                entriesSection
                    .zIndex(10) // entry editor's inline project picker floats above projects/reports/export
                BrutalistDivider()

                projectsSection
                BrutalistDivider()

                reportsSection
                BrutalistDivider()

                exportSection
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, BrutalistTheme.padding)
            .padding(.bottom, BrutalistTheme.padding)
        }
        .frame(width: 400, height: 610)
        .background(BrutalistTheme.bg)
        .background(KeyEventCatcher(handler: handleKey))
        .environment(\.calendar, appState.days.calendar)
        .environment(\.timeZone, appState.days.calendar.timeZone)
        .onTapGesture {
            if projectPickerOpen { projectPickerOpen = false }
            if editSession.projectPickerOpen { editSession.projectPickerOpen = false }
        }
    }

    // MARK: - Keyboard

    private enum KeyCode {
        static let space: UInt16 = 49
        static let n: UInt16     = 45
        static let p: UInt16     = 35
        static let e: UInt16     = 14
        static let t: UInt16     = 17
        static let escape: UInt16 = 53
        static let leftArrow: UInt16  = 123
        static let rightArrow: UInt16 = 124
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let isTextFocused = event.window?.firstResponder is NSText

        // esc is the only key we handle while a text field is focused.
        if isTextFocused && event.keyCode != KeyCode.escape { return event }

        switch event.keyCode {
        case KeyCode.space:
            if appState.runningEntry == nil {
                appState.startTimer()
            } else {
                confirmingStop = true
            }
            return nil
        case KeyCode.n: // new entry: open picker; start timer on next selection
            if appState.runningEntry == nil {
                startAfterProjectPick = true
                projectPickerOpen = true
            }
            return nil
        case KeyCode.p: // open project picker
            projectPickerOpen = true
            return nil
        case KeyCode.e: // edit currently running entry
            if let running = appState.runningEntry {
                editSession.begin(running)
            }
            return nil
        case KeyCode.leftArrow: // browse to the previous day
            showDay(step: -1)
            return nil
        case KeyCode.rightArrow: // browse to the next day, never past today
            showDay(step: 1)
            return nil
        case KeyCode.t: // back to today
            editSession.clear()
            appState.showToday()
            return nil
        case KeyCode.escape: // close open editor/picker/confirm, in priority order
            if editSession.entryId != nil { editSession.clear(); return nil }
            if editSession.projectPickerOpen { editSession.projectPickerOpen = false; return nil }
            if projectPickerOpen { startAfterProjectPick = false; projectPickerOpen = false; return nil }
            if confirmingStop { confirmingStop = false; return nil }
            if confirmingArchiveId != nil { confirmingArchiveId = nil; return nil }
            if addingProject { cancelAddProject(); return nil }
            return event
        default:
            return event
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            HeaderProjectPicker(
                projects: appState.projects,
                selectedId: Binding(
                    get: { appState.selectedProjectId },
                    set: { newId in
                        guard let id = newId else { return }
                        appState.selectProject(id: id)
                        if startAfterProjectPick, appState.runningEntry == nil {
                            appState.startTimer()
                        }
                        startAfterProjectPick = false
                    }
                ),
                allTimeSeconds: { appState.projectAllTimeSeconds(for: $0) },
                onCreateProject: { appState.createProject(name: $0) },
                isOpen: $projectPickerOpen
            )
            Spacer()
            metaText
        }
    }

    private var metaText: some View {
        HStack(spacing: 6) {
            if let started = appState.startedAt {
                Text("started \(Self.timeFormatter.string(from: started))")
                    .font(BrutalistTheme.metaFont)
                    .foregroundColor(BrutalistTheme.dim)
                    .textCase(.uppercase)
                    .kerning(1.3)
            } else if let idle = appState.idleSeconds {
                Text("idle \(HMS.idleHours(idle))")
                    .font(BrutalistTheme.metaFont)
                    .foregroundColor(BrutalistTheme.dim)
                    .textCase(.uppercase)
                    .kerning(1.3)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.fg)
                .lineLimit(2)
            Spacer()
            BrutalistTextButton(title: "dismiss", muted: true) {
                appState.dismissError()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(BrutalistTheme.accent.opacity(0.15))
        .overlay(
            Rectangle()
                .strokeBorder(BrutalistTheme.accent, lineWidth: 1)
        )
    }

    // MARK: - Timer

    private var timerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            timerDisplay
            Spacer()
            if confirmingStop {
                HStack(spacing: 6) {
                    Text("stop timer?")
                        .font(BrutalistTheme.metaFont)
                        .foregroundColor(BrutalistTheme.dim2)
                        .textCase(.uppercase)
                        .kerning(1.3)
                    BrutalistTextButton(title: "yes") {
                        appState.stopTimer()
                        confirmingStop = false
                    }
                    BrutalistTextButton(title: "no", muted: true) {
                        confirmingStop = false
                    }
                }
            } else if appState.runningEntry == nil {
                BrutalistTextButton(title: "start ▶") {
                    appState.startTimer()
                }
            } else {
                BrutalistTextButton(title: "stop ■") {
                    confirmingStop = true
                }
            }
        }
    }

    private var timerDisplay: some View {
        let text = HMS.hoursMinutesSeconds(appState.elapsedSeconds)
        return Text(colorizeTimer(text))
            .font(BrutalistTheme.timerMainFont)
            .kerning(-0.3)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }

    private func colorizeTimer(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.foregroundColor = BrutalistTheme.fg
        for char in [":"] {
            var search = attr.startIndex
            while let range = attr[search...].range(of: char) {
                attr[range].foregroundColor = BrutalistTheme.colonDim
                search = range.upperBound
            }
        }
        return attr
    }

    // MARK: - Entries

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BrutalistTextButton(title: "←") { showDay(step: -1) }
                Button {
                    editSession.clear()
                    appState.showToday()
                } label: {
                    SectionHeader(title: dayLabel)
                }
                .buttonStyle(.plain)
                if appState.isViewingToday {
                    Text("→")
                        .font(BrutalistTheme.buttonFont)
                        .kerning(1.5)
                        .foregroundColor(BrutalistTheme.colonDim)
                } else {
                    BrutalistTextButton(title: "→") { showDay(step: 1) }
                }
                Spacer()
                let count = appState.visibleEntries.count
                let total = appState.visibleDayTotalSeconds()
                if count > 0 {
                    Text("\(count) \(count == 1 ? "entry" : "entries") · \(HMS.hoursMinutes(total))")
                        .font(BrutalistTheme.metaFont)
                        .foregroundColor(BrutalistTheme.dim)
                        .textCase(.uppercase)
                        .kerning(1.1)
                }
            }

            if appState.visibleEntries.isEmpty {
                Text("no entries")
                    .font(BrutalistTheme.bodyFont)
                    .foregroundColor(BrutalistTheme.dim)
            } else {
                ForEach(appState.visibleEntries) { entry in
                    if editSession.entryId == entry.id {
                        entryEditor(for: entry)
                    } else {
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private var dayLabel: String {
        guard !appState.isViewingToday else { return "today" }
        return Self.dayLabelFormatter.string(from: appState.selectedDay).lowercased()
    }

    private func showDay(step: Int) {
        guard step < 0 || !appState.isViewingToday else { return }
        editSession.clear()
        appState.stepDay(by: step)
    }

    private func entryRow(_ entry: TimeEntry) -> some View {
        let duration = TimeMath.durationSeconds(start: entry.start, end: entry.end, now: appState.days.now)
        let isRunning = appState.runningEntry?.id == entry.id
        return HStack(spacing: 8) {
            Text(entry.end == nil
                 ? "\(Self.timeFormatter.string(from: entry.start)) →"
                 : Self.timeFormatter.string(from: entry.start))
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.dim2)
                .frame(width: 62, alignment: .leading)
                .monospacedDigit()

            Text(appState.projectName(for: entry.projectId))
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.fg)
                .lineLimit(1)
                .truncationMode(.tail)

            DottedLeader()

            HStack(spacing: 4) {
                Text(HMS.hoursMinutesSeconds(duration))
                    .font(BrutalistTheme.bodyFont)
                    .foregroundColor(BrutalistTheme.fg)
                    .monospacedDigit()
                if isRunning {
                    Text("●")
                        .font(BrutalistTheme.bodyFont)
                        .foregroundColor(BrutalistTheme.accent)
                }
            }

            BrutalistTextButton(title: "edit", muted: true) {
                editSession.begin(entry)
            }
        }
        .padding(.vertical, BrutalistTheme.rowVerticalPadding)
    }

    // MARK: - Entry Editor

    @ViewBuilder
    private func entryEditor(for entry: TimeEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                editField(label: "start", text: $editSession.startText, width: 58, onCommit: { editSession.commit(.start) })
                editField(label: "end", text: $editSession.endText, width: 58, onCommit: { editSession.commit(.end) })
                editField(label: "dur", text: $editSession.durationText, width: 82, onCommit: { editSession.commit(.duration) })
                Spacer()
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("project →")
                        .font(BrutalistTheme.labelFont)
                        .foregroundColor(BrutalistTheme.dim)
                        .textCase(.uppercase)
                        .kerning(1.5)
                    editorProjectPicker
                }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("note")
                        .font(BrutalistTheme.labelFont)
                        .foregroundColor(BrutalistTheme.dim)
                        .textCase(.uppercase)
                        .kerning(1.5)
                    TextField("", text: $editSession.note)
                        .textFieldStyle(.plain)
                        .font(BrutalistTheme.bodyFont)
                        .foregroundColor(BrutalistTheme.fg)
                        .padding(.vertical, 2)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(BrutalistTheme.border)
                        }
                }
            }
            HStack {
                BrutalistTextButton(title: "delete entry", danger: true) {
                    appState.deleteEntry(id: entry.id)
                    editSession.clear()
                }
                Spacer()
                BrutalistTextButton(title: "cancel", muted: true) {
                    editSession.clear()
                }
                BrutalistTextButton(title: "save") {
                    saveEdit(entry)
                }
            }
        }
        .brutalistSurface(vertical: 10, horizontal: 12)
        .padding(.vertical, 4)
    }

    private func editField(label: String, text: Binding<String>, width: CGFloat, onCommit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(BrutalistTheme.labelFont)
                .foregroundColor(BrutalistTheme.dim)
                .textCase(.uppercase)
                .kerning(1.5)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.fg)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: width)
                .padding(.vertical, 2)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(BrutalistTheme.border)
                }
                .onSubmit(onCommit)
        }
    }

    private var editorProjectPicker: some View {
        HeaderProjectPicker(
            projects: appState.projects,
            selectedId: Binding(
                get: { editSession.projectId },
                set: { editSession.projectId = $0 }
            ),
            allTimeSeconds: { appState.projectAllTimeSeconds(for: $0) },
            onCreateProject: { name in
                appState.createProject(name: name)
                if let created = appState.projects.last(where: { $0.name.lowercased() == name.lowercased() }) {
                    editSession.projectId = created.id
                }
            },
            isOpen: $editSession.projectPickerOpen
        )
    }

    private func saveEdit(_ entry: TimeEntry) {
        guard let update = editSession.update(runningEntryId: appState.runningEntry?.id, currentEnd: entry.end) else { return }
        appState.updateEntry(id: update.id, start: update.start, end: update.end, note: update.note, projectId: update.projectId)
        editSession.clear()
    }

    // MARK: - Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
            SectionHeader(title: "projects")

            ForEach(appState.projects) { project in
                projectRow(project)
            }

            if addingProject {
                projectAddRow
            } else {
                Button(action: {
                    addingProject = true
                    newProjectFocused = true
                }) {
                    HStack(spacing: 4) {
                        Text("+")
                            .font(BrutalistTheme.bodyFont)
                            .foregroundColor(BrutalistTheme.accent)
                        Text("new project")
                            .font(BrutalistTheme.bodyFont)
                            .foregroundColor(BrutalistTheme.dim2)
                        DottedLeader()
                        Text("add")
                            .font(BrutalistTheme.bodyFont)
                            .foregroundColor(BrutalistTheme.dim)
                    }
                    .padding(.vertical, BrutalistTheme.rowVerticalPadding)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Text(project.name.lowercased())
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.fg)
                .lineLimit(1)
                .truncationMode(.tail)
            DottedLeader()
            Text(HMS.hoursMinutes(appState.projectAllTimeSeconds(for: project.id)))
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.dim2)
                .monospacedDigit()
            if confirmingArchiveId == project.id {
                HStack(spacing: 6) {
                    Text("archive \"\(project.name.lowercased())\"?")
                        .font(BrutalistTheme.metaFont)
                        .foregroundColor(BrutalistTheme.dim2)
                    BrutalistTextButton(title: "yes", danger: true) {
                        appState.archiveProject(id: project.id)
                        confirmingArchiveId = nil
                    }
                    BrutalistTextButton(title: "no", muted: true) {
                        confirmingArchiveId = nil
                    }
                }
            } else {
                BrutalistTextButton(title: "archive", muted: true) {
                    confirmingArchiveId = project.id
                }
            }
        }
        .padding(.vertical, BrutalistTheme.rowVerticalPadding)
    }

    private var projectAddRow: some View {
        HStack(spacing: 6) {
            Text("+")
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.accent)
            TextField("project name…", text: $newProjectName)
                .textFieldStyle(.plain)
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.fg)
                .focused($newProjectFocused)
                .onSubmit(commitAddProject)
            Spacer()
            Text("⏎ add · esc cancel")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(BrutalistTheme.dim)
        }
        .brutalistSurface(vertical: 6, horizontal: 10)
        .onExitCommand(perform: cancelAddProject)
    }

    private func commitAddProject() {
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.createProject(name: trimmed)
        newProjectName = ""
        addingProject = false
        newProjectFocused = false
    }

    private func cancelAddProject() {
        newProjectName = ""
        addingProject = false
        newProjectFocused = false
    }

    // MARK: - Reports

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.groupSpacing) {
            SectionHeader(title: "reports")

            HStack(spacing: 8) {
                Text("today")
                    .font(BrutalistTheme.bodyFont)
                    .foregroundColor(BrutalistTheme.dim2)
                DottedLeader()
                Text(HMS.hoursMinutes(appState.todayTotalSeconds()))
                    .font(BrutalistTheme.bodyFont)
                    .foregroundColor(BrutalistTheme.fg)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Text("week")
                    .font(BrutalistTheme.bodyFont)
                    .foregroundColor(BrutalistTheme.dim2)
                DottedLeader()
                Text(HMS.hoursMinutes(weekTotalSeconds()))
                    .font(BrutalistTheme.bodyFont)
                    .foregroundColor(BrutalistTheme.fg)
                    .monospacedDigit()
            }

            weekChart
                .padding(.top, 6)
        }
    }

    private func weekTotalSeconds() -> Int {
        appState.weeklyTotals().reduce(0) { $0 + $1.seconds }
    }

    private var weekChart: some View {
        let totals = appState.weeklyTotals()
        let maxSeconds = max(1, totals.map(\.seconds).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(totals) { day in
                let isToday = appState.days.isToday(day.date)
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        Rectangle()
                            .fill(BrutalistTheme.surface)
                            .frame(height: 36)
                        Rectangle()
                            .fill(isToday ? BrutalistTheme.accent : BrutalistTheme.fg)
                            .frame(height: barHeight(seconds: day.seconds, maxSeconds: maxSeconds))
                    }
                    Text(Self.dayFormatter.string(from: day.date).lowercased())
                        .font(BrutalistTheme.metaFont)
                        .foregroundColor(isToday ? BrutalistTheme.fg : BrutalistTheme.dim)
                    Text(formatBarLabel(day.seconds))
                        .font(BrutalistTheme.metaFont)
                        .foregroundColor(isToday ? BrutalistTheme.fg : BrutalistTheme.dim)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func barHeight(seconds: Int, maxSeconds: Int) -> CGFloat {
        guard seconds > 0 else { return 0 }
        let ratio = min(1.0, Double(seconds) / Double(maxSeconds))
        return max(2, CGFloat(ratio) * 36)
    }

    private func formatBarLabel(_ seconds: Int) -> String {
        if seconds <= 0 { return "—" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    // MARK: - Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
            SectionHeader(title: "export")

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("from")
                        .font(BrutalistTheme.bodyFont)
                        .foregroundColor(BrutalistTheme.dim2)
                    chip(date: $exportStart)
                }
                HStack(spacing: 6) {
                    Text("to")
                        .font(BrutalistTheme.bodyFont)
                        .foregroundColor(BrutalistTheme.dim2)
                    chip(date: $exportEnd)
                }
                Spacer()
                BrutalistTextButton(title: "export ↗") { exportCSV() }
            }
        }
    }

    private func chip(date: Binding<Date>) -> some View {
        DatePicker("", selection: date, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.field)
            .controlSize(.mini)
            .font(BrutalistTheme.bodyFont)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(BrutalistTheme.surface)
            .overlay(
                Rectangle()
                    .strokeBorder(BrutalistTheme.border, lineWidth: 1)
            )
    }

    private func exportCSV() {
        let range = appState.days.range(from: exportStart, through: exportEnd)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "tt-export.csv"
        if panel.runModal() == .OK, let url = panel.url {
            appState.exportCSV(range: range, to: url)
        }
    }
}
