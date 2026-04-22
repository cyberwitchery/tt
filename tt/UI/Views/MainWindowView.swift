import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainWindowView: View {
    @ObservedObject var appState: AppState

    // Picker state
    @State private var projectPickerOpen = false

    // Timer confirm
    @State private var confirmingStop = false

    // Entry editor
    @State private var editingEntryId: String?
    @State private var editFields = EntryEditor.Fields(startSeconds: 0, endSeconds: 0, durationSeconds: 0)
    @State private var editProjectId: String?
    @State private var editNote = ""
    @State private var editStartText = ""
    @State private var editEndText = ""
    @State private var editDurText = ""
    @State private var editProjectPickerOpen = false

    // Projects section
    @State private var addingProject = false
    @State private var newProjectName = ""
    @FocusState private var newProjectFocused: Bool
    @State private var confirmingArchiveId: String?

    // Export
    @State private var exportStart: Date = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var exportEnd: Date = Date()

    // Keyboard flow: after user picks a project via the N shortcut, start timer.
    @State private var startAfterProjectPick = false

    // Week day labels (Mon..Sun, localized short)
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EE"
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
                headerRow
                    .padding(.top, 40)
                    .zIndex(20) // header dropdown must float above later sections
                timerRow
                    .padding(.top, 14)
                BrutalistDivider()

                todaySection
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
        .onTapGesture {
            if projectPickerOpen { projectPickerOpen = false }
            if editProjectPickerOpen { editProjectPickerOpen = false }
        }
    }

    // MARK: - Keyboard

    private enum KeyCode {
        static let space: UInt16 = 49
        static let n: UInt16     = 45
        static let p: UInt16     = 35
        static let e: UInt16     = 14
        static let escape: UInt16 = 53
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let isTextFocused = event.window?.firstResponder is NSText

        // Esc is the only key we handle while a text field is focused.
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
        case KeyCode.p: // focus project picker
            projectPickerOpen = true
            return nil
        case KeyCode.e: // edit currently running entry
            if let running = appState.runningEntry {
                beginEdit(running)
            }
            return nil
        case KeyCode.escape: // close open editor/picker/confirm, in priority order
            if editingEntryId != nil { clearEdit(); return nil }
            if editProjectPickerOpen { editProjectPickerOpen = false; return nil }
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

    // MARK: - Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "today")
                Spacer()
                let count = appState.todaysEntries.count
                let total = todaysTotalSeconds()
                if count > 0 {
                    Text("\(count) \(count == 1 ? "entry" : "entries") · \(HMS.hoursMinutes(total))")
                        .font(BrutalistTheme.metaFont)
                        .foregroundColor(BrutalistTheme.dim)
                        .textCase(.uppercase)
                        .kerning(1.1)
                }
            }

            if appState.todaysEntries.isEmpty {
                Text("no entries")
                    .font(BrutalistTheme.bodyFont)
                    .foregroundColor(BrutalistTheme.dim)
            } else {
                ForEach(appState.todaysEntries) { entry in
                    if editingEntryId == entry.id {
                        entryEditor(for: entry)
                    } else {
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private func todaysTotalSeconds() -> Int {
        appState.todaysEntries.reduce(0) { sum, entry in
            sum + TimeMath.durationSeconds(start: entry.start, end: entry.end)
        }
    }

    private func entryRow(_ entry: TimeEntry) -> some View {
        let duration = TimeMath.durationSeconds(start: entry.start, end: entry.end)
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
                beginEdit(entry)
            }
        }
        .padding(.vertical, BrutalistTheme.rowVerticalPadding)
    }

    // MARK: - Entry Editor

    @ViewBuilder
    private func entryEditor(for entry: TimeEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                editField(label: "start", text: $editStartText, width: 58, onCommit: commitStart)
                editField(label: "end", text: $editEndText, width: 58, onCommit: commitEnd)
                editField(label: "dur", text: $editDurText, width: 82, onCommit: commitDur)
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
                    TextField("", text: $editNote)
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
                    clearEdit()
                }
                Spacer()
                BrutalistTextButton(title: "cancel", muted: true) {
                    clearEdit()
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
                get: { editProjectId },
                set: { editProjectId = $0 }
            ),
            allTimeSeconds: { appState.projectAllTimeSeconds(for: $0) },
            onCreateProject: { name in
                appState.createProject(name: name)
                if let created = appState.projects.last(where: { $0.name.lowercased() == name.lowercased() }) {
                    editProjectId = created.id
                }
            },
            isOpen: $editProjectPickerOpen
        )
    }

    private func beginEdit(_ entry: TimeEntry) {
        editingEntryId = entry.id
        editProjectId = entry.projectId
        editNote = entry.note ?? ""
        editFields = EntryEditor.fields(start: entry.start, end: entry.end)
        syncEditTexts()
    }

    private func clearEdit() {
        editingEntryId = nil
        editProjectPickerOpen = false
        editNote = ""
    }

    private func syncEditTexts() {
        editStartText = formatHHMM(editFields.startSeconds)
        editEndText = formatHHMM(editFields.endSeconds)
        editDurText = formatHHMMSS(editFields.durationSeconds)
    }

    private func commitStart() {
        if let sec = parseHHMM(editStartText) {
            editFields = EntryEditor.withStart(editFields, seconds: sec)
        }
        syncEditTexts()
    }

    private func commitEnd() {
        if let sec = parseHHMM(editEndText) {
            editFields = EntryEditor.withEnd(editFields, seconds: sec)
        }
        syncEditTexts()
    }

    private func commitDur() {
        if let sec = parseHHMMSS(editDurText) {
            editFields = EntryEditor.withDuration(editFields, seconds: sec)
        }
        syncEditTexts()
    }

    private func saveEdit(_ entry: TimeEntry) {
        commitStart(); commitEnd(); commitDur()
        let (start, end) = EntryEditor.resolve(editFields, baseDate: entry.start)
        let isRunning = appState.runningEntry?.id == entry.id
        let newProjectId = editProjectId ?? entry.projectId
        if newProjectId != entry.projectId {
            // TimeTracker.updateEntry doesn't currently touch projectId. For
            // minimal risk, update project through a separate path if needed.
            // For now accept the change; the repo.update writes the full row.
        }
        appState.updateEntry(
            id: entry.id,
            start: start,
            end: isRunning ? nil : end,
            note: editNote,
            projectId: newProjectId
        )
        clearEdit()
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
                Text(HMS.hoursMinutes(todaysTotalSeconds()))
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
        appState.weeklyTotals.reduce(0) { $0 + $1.seconds }
    }

    private var weekChart: some View {
        let maxSeconds = max(1, appState.weeklyTotals.map(\.seconds).max() ?? 1)
        let today = Calendar.current.startOfDay(for: Date())
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(appState.weeklyTotals) { day in
                let isToday = Calendar.current.isDate(day.date, inSameDayAs: today)
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
        let start = min(exportStart, exportEnd)
        let end = max(exportStart, exportEnd)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "tt-export.csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? appState.exportCSV(range: start..<end.addingTimeInterval(86400), to: url)
        }
    }

    // MARK: - HH:MM parsing

    private func parseHHMM(_ text: String) -> Int? {
        let parts = text.split(separator: ":").map(String.init)
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              h >= 0, h < 24, m >= 0, m < 60 else { return nil }
        return h * 3600 + m * 60
    }

    private func parseHHMMSS(_ text: String) -> Int? {
        let parts = text.split(separator: ":").map(String.init)
        if parts.count == 3,
           let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]),
           h >= 0, m >= 0, m < 60, s >= 0, s < 60 {
            return h * 3600 + m * 60 + s
        }
        if parts.count == 2,
           let h = Int(parts[0]), let m = Int(parts[1]),
           h >= 0, m >= 0, m < 60 {
            return h * 3600 + m * 60
        }
        return nil
    }

    private func formatHHMM(_ seconds: Int) -> String {
        let h = (seconds / 3600) % 24
        let m = (seconds % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }

    private func formatHHMMSS(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
