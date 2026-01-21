import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var newProjectName = ""
    @State private var editingEntryId: String?
    @State private var editStart = Date()
    @State private var editEnd = Date()
    @State private var editNote = ""
    @State private var exportStart = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var exportEnd = Calendar.current.dateInterval(of: .month, for: Date())?.end ?? Date()
    @State private var confirmingDeleteId: String?
    @State private var confirmingArchiveId: String?
    @FocusState private var isProjectFieldFocused: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrutalistTheme.sectionSpacing) {
                timerSection
                BrutalistDivider()
                entriesSection
                BrutalistDivider()
                projectsSection
                BrutalistDivider()
                reportsSection
                BrutalistDivider()
                exportSection
            }
            .padding(BrutalistTheme.padding)
        }
        .frame(width: 400, height: 610)
        .background(BrutalistTheme.background(for: colorScheme))
        .onAppear {
            DispatchQueue.main.async { isProjectFieldFocused = false }
        }
    }

    // MARK: - Timer (Hero)

    private var timerSection: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.groupSpacing) {
            // Project picker
            HStack(spacing: BrutalistTheme.tightSpacing) {
                Text("project")
                    .brutalistMuted(colorScheme)
                BrutalistPicker(
                    items: appState.projects,
                    selection: Binding(
                        get: { appState.selectedProjectId },
                        set: { if let id = $0 { appState.selectProject(id: id) } }
                    ),
                    itemLabel: { $0.name.lowercased() }
                )
            }

            // Timer display - THE HERO
            HStack(alignment: .firstTextBaseline) {
                Text(TimeMath.formatHMS(seconds: appState.elapsedSeconds))
                    .font(BrutalistTheme.displayFont)
                    .foregroundColor(BrutalistTheme.foreground(for: colorScheme))

                Spacer()

                if appState.runningEntry == nil {
                    BrutalistTextButton(title: "start", action: { appState.startTimer() })
                } else {
                    BrutalistTextButton(title: "stop", action: { appState.stopTimer() })
                }
            }
        }
    }

    // MARK: - Entries

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
            SectionHeader(title: "Today")

            if appState.todaysEntries.isEmpty {
                Text("no entries")
                    .brutalistMuted(colorScheme)
            } else {
                ForEach(appState.todaysEntries) { entry in
                    entryRow(entry)
                }
            }

            if let id = editingEntryId,
               let entry = appState.todaysEntries.first(where: { $0.id == id }) {
                editForm(entry)
            }
        }
    }

    private func entryRow(_ entry: TimeEntry) -> some View {
        HStack(alignment: .top) {
            // Time column
            Text(timeRange(entry))
                .brutalistCaption(colorScheme)
                .frame(width: 90, alignment: .leading)

            // Project + note
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: BrutalistTheme.tightSpacing) {
                    Text(appState.projectName(for: entry.projectId))
                        .brutalistBody(colorScheme)
                    if appState.runningEntry?.id == entry.id {
                        Text("•")
                            .brutalistCaption(colorScheme)
                    }
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .brutalistMuted(colorScheme)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: BrutalistTheme.tightSpacing) {
                BrutalistTextButton(title: "edit", muted: true) { beginEdit(entry) }
                if confirmingDeleteId == entry.id {
                    BrutalistTextButton(title: "delete?") {
                        appState.deleteEntry(id: entry.id)
                        confirmingDeleteId = nil
                    }
                } else {
                    BrutalistTextButton(title: "×", muted: true) {
                        confirmingDeleteId = entry.id
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func editForm(_ entry: TimeEntry) -> some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
            BrutalistDivider()

            HStack {
                Text("start")
                    .brutalistMuted(colorScheme)
                    .frame(width: 36, alignment: .leading)
                DatePicker("", selection: $editStart, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .controlSize(.mini)
            }

            HStack {
                Text("end")
                    .brutalistMuted(colorScheme)
                    .frame(width: 36, alignment: .leading)
                DatePicker("", selection: $editEnd, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .controlSize(.mini)
            }

            HStack {
                Text("note")
                    .brutalistMuted(colorScheme)
                    .frame(width: 36, alignment: .leading)
                TextField("", text: $editNote)
                    .textFieldStyle(.plain)
                    .brutalistBody(colorScheme)
            }

            HStack(spacing: BrutalistTheme.tightSpacing) {
                BrutalistTextButton(title: "save") {
                    let isRunning = appState.runningEntry?.id == entry.id
                    appState.updateEntry(id: entry.id, start: editStart, end: isRunning ? nil : editEnd, note: editNote)
                    clearEdit()
                }
                BrutalistTextButton(title: "cancel", muted: true) { clearEdit() }
            }
        }
    }

    // MARK: - Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
            SectionHeader(title: "Projects")

            HStack(spacing: BrutalistTheme.tightSpacing) {
                TextField("new project", text: $newProjectName)
                    .textFieldStyle(.plain)
                    .brutalistBody(colorScheme)
                    .focused($isProjectFieldFocused)
                    .onSubmit { addProject() }
                BrutalistTextButton(title: "add") { addProject() }
            }

            ForEach(appState.projects) { project in
                HStack {
                    Text(project.name.lowercased())
                        .brutalistBody(colorScheme)
                    Spacer()
                    if confirmingArchiveId == project.id {
                        BrutalistTextButton(title: "archive?") {
                            appState.archiveProject(id: project.id)
                            confirmingArchiveId = nil
                        }
                    } else {
                        BrutalistTextButton(title: "archive", muted: true) {
                            confirmingArchiveId = project.id
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reports

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.groupSpacing) {
            SectionHeader(title: "Reports")

            // Today
            VStack(alignment: .leading, spacing: BrutalistTheme.tightSpacing) {
                Text("today")
                    .brutalistMuted(colorScheme)

                if appState.dailyTotals.isEmpty {
                    Text("—")
                        .brutalistMuted(colorScheme)
                } else {
                    ForEach(appState.dailyTotals) { total in
                        HStack {
                            Text(total.name.lowercased())
                                .brutalistBody(colorScheme)
                            Spacer()
                            Text(TimeMath.formatHMS(seconds: total.seconds))
                                .brutalistCaption(colorScheme)
                        }
                    }
                }
            }

            // Week
            VStack(alignment: .leading, spacing: BrutalistTheme.tightSpacing) {
                HStack {
                    Text("week")
                        .brutalistMuted(colorScheme)
                    Spacer()
                    Text(TimeMath.formatHMS(seconds: weekTotal()))
                        .brutalistBody(colorScheme)
                }

                HStack(spacing: 0) {
                    ForEach(appState.weeklyTotals) { day in
                        VStack(spacing: 2) {
                            Text(Self.dayFormatter.string(from: day.date).lowercased())
                                .brutalistMuted(colorScheme)
                            Text(formatHours(day.seconds))
                                .brutalistCaption(colorScheme)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
            SectionHeader(title: "Export")

            HStack(spacing: BrutalistTheme.groupSpacing) {
                HStack(spacing: BrutalistTheme.tightSpacing) {
                    Text("from")
                        .brutalistMuted(colorScheme)
                    DatePicker("", selection: $exportStart, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .controlSize(.mini)
                }

                HStack(spacing: BrutalistTheme.tightSpacing) {
                    Text("to")
                        .brutalistMuted(colorScheme)
                    DatePicker("", selection: $exportEnd, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .controlSize(.mini)
                }

                Spacer()

                BrutalistTextButton(title: "export") { exportCSV() }
            }
        }
    }

    // MARK: - Helpers

    private func timeRange(_ entry: TimeEntry) -> String {
        let start = Self.timeFormatter.string(from: entry.start)
        if entry.end == nil {
            return "\(start) →"
        }
        let end = Self.timeFormatter.string(from: entry.end!)
        return "\(start) – \(end)"
    }

    private func formatHours(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 {
            return "\(h)h"
        } else if m > 0 {
            return "\(m)m"
        }
        return "—"
    }

    private func weekTotal() -> Int {
        appState.weeklyTotals.reduce(0) { $0 + $1.seconds }
    }

    private func beginEdit(_ entry: TimeEntry) {
        editingEntryId = entry.id
        editStart = entry.start
        editEnd = entry.end ?? Date()
        editNote = entry.note ?? ""
    }

    private func clearEdit() {
        editingEntryId = nil
        editNote = ""
    }

    private func addProject() {
        guard !newProjectName.isEmpty else { return }
        appState.createProject(name: newProjectName)
        newProjectName = ""
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
}
