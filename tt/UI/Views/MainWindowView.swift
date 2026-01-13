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
    @State private var isEndSet = false
    @State private var editNote = ""
    @State private var exportStart = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var exportEnd = Calendar.current.dateInterval(of: .month, for: Date())?.end ?? Date()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.sectionSpacing) {
            VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
                Text("today")
                    .font(BrutalistTheme.sectionFont)
                    .foregroundColor(BrutalistTheme.foreground(for: colorScheme))

                Grid(alignment: .leading, horizontalSpacing: BrutalistTheme.tightPadding, verticalSpacing: BrutalistTheme.rowSpacing) {
                    GridRow {
                        Text("project")
                            .font(BrutalistTheme.labelFont)
                            .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                            .frame(width: 56, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { appState.selectedProjectId ?? "" },
                            set: { appState.selectProject(id: $0) }
                        )) {
                            ForEach(appState.projects) { project in
                                Text(project.name.lowercased()).tag(project.id)
                            }
                        }
                        .labelsHidden()
                        .font(BrutalistTheme.bodyFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GridRow {
                        Text("timer")
                            .font(BrutalistTheme.labelFont)
                            .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                            .frame(width: 56, alignment: .leading)

                        HStack(spacing: BrutalistTheme.tightPadding) {
                            Spacer()
                            Text(TimeMath.formatHMS(seconds: appState.elapsedSeconds))
                                .font(BrutalistTheme.sectionFont)
                                .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
                                .frame(minWidth: 80, alignment: .trailing)

                            if appState.runningEntry == nil {
                                BrutalistTextButton(title: "start") {
                                    appState.startTimer()
                                }
                            } else {
                                BrutalistTextButton(title: "stop") {
                                    appState.stopTimer()
                                }
                            }
                        }
                    }
                }

                if appState.todaysEntries.isEmpty {
                    Text("no entries today")
                        .font(BrutalistTheme.labelFont)
                        .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                } else {
                    ForEach(appState.todaysEntries) { entry in
                        HStack(spacing: BrutalistTheme.tightPadding) {
                            Text(entryTimeLabel(entry))
                                .font(BrutalistTheme.labelFont)
                                .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                            Text(appState.projectName(for: entry.projectId))
                                .font(BrutalistTheme.bodyFont)
                                .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
                            if appState.runningEntry?.id == entry.id {
                                Text("running")
                                    .font(BrutalistTheme.labelFont)
                                    .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                            }
                            if let note = entry.note, !note.isEmpty {
                                Text("— \(note)")
                                    .font(BrutalistTheme.labelFont)
                                    .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                            }
                            Spacer()
                            BrutalistTextButton(title: "edit") {
                                beginEdit(entry)
                            }
                            BrutalistTextButton(title: "delete") {
                                appState.deleteEntry(id: entry.id)
                            }
                        }
                    }
                }

                if let editingEntryId, let editingEntry = appState.todaysEntries.first(where: { $0.id == editingEntryId }) {
                    SectionDivider()

                    Text("edit entry")
                        .font(BrutalistTheme.labelFont)
                        .foregroundColor(BrutalistTheme.secondary(for: colorScheme))

                    VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
                        HStack(spacing: BrutalistTheme.tightPadding) {
                            Text("start")
                                .font(BrutalistTheme.labelFont)
                                .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                            DatePicker(
                                "",
                                selection: $editStart,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .font(BrutalistTheme.bodyFont)
                        }

                        HStack(spacing: BrutalistTheme.tightPadding) {
                            Text("end")
                                .font(BrutalistTheme.labelFont)
                                .foregroundColor(BrutalistTheme.secondary(for: colorScheme))

                            Toggle("set", isOn: $isEndSet)
                                .toggleStyle(.checkbox)
                                .labelsHidden()

                            if isEndSet {
                                DatePicker(
                                    "",
                                    selection: $editEnd,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .font(BrutalistTheme.bodyFont)
                            } else if appState.runningEntry != nil && appState.runningEntry?.id != editingEntry.id {
                                Text("running elsewhere")
                                    .font(BrutalistTheme.labelFont)
                                    .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                            }
                        }

                        HStack(spacing: BrutalistTheme.tightPadding) {
                            Text("note")
                                .font(BrutalistTheme.labelFont)
                                .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                            TextField("optional", text: $editNote)
                                .textFieldStyle(.plain)
                                .font(BrutalistTheme.labelFont)
                                .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
                                .padding(.vertical, BrutalistTheme.tightPadding)
                                .overlay(
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(BrutalistTheme.secondary(for: colorScheme)),
                                    alignment: .bottom
                                )
                        }

                        HStack(spacing: BrutalistTheme.tightPadding) {
                            BrutalistTextButton(title: "save") {
                                let resolvedEnd = resolveEnd(for: editingEntry)
                                appState.updateEntry(
                                    id: editingEntry.id,
                                    start: editStart,
                                    end: resolvedEnd,
                                    note: editNote
                                )
                                clearEdit()
                            }
                            BrutalistTextButton(title: "cancel") {
                                clearEdit()
                            }
                        }
                    }
                }
            }

            SectionDivider()

            VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
                Text("projects")
                    .font(BrutalistTheme.sectionFont)
                    .foregroundColor(BrutalistTheme.foreground(for: colorScheme))

                HStack(spacing: BrutalistTheme.tightPadding) {
                    TextField("new project", text: $newProjectName)
                        .textFieldStyle(.plain)
                        .font(BrutalistTheme.bodyFont)
                        .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
                        .padding(.vertical, BrutalistTheme.tightPadding)
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(BrutalistTheme.secondary(for: colorScheme)),
                            alignment: .bottom
                        )
                        .onSubmit {
                            appState.createProject(name: newProjectName)
                            newProjectName = ""
                        }

                    BrutalistTextButton(title: "add") {
                        appState.createProject(name: newProjectName)
                        newProjectName = ""
                    }
                }

                if appState.projects.isEmpty {
                    Text("no projects")
                        .font(BrutalistTheme.labelFont)
                        .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                } else {
                    ForEach(appState.projects) { project in
                        HStack(spacing: BrutalistTheme.tightPadding) {
                            Text(project.name.lowercased())
                                .font(BrutalistTheme.bodyFont)
                                .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
                            Spacer()
                            BrutalistTextButton(title: "archive") {
                                appState.archiveProject(id: project.id)
                            }
                        }
                    }
                }
            }

            SectionDivider()

            VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
                Text("reports")
                    .font(BrutalistTheme.sectionFont)
                    .foregroundColor(BrutalistTheme.foreground(for: colorScheme))

                Text("daily totals")
                    .font(BrutalistTheme.labelFont)
                    .foregroundColor(BrutalistTheme.secondary(for: colorScheme))

                if appState.dailyTotals.isEmpty {
                    Text("no data")
                        .font(BrutalistTheme.labelFont)
                        .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                } else {
                    ForEach(appState.dailyTotals) { total in
                        HStack(spacing: BrutalistTheme.tightPadding) {
                            Text(total.name.lowercased())
                                .font(BrutalistTheme.bodyFont)
                                .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
                            Spacer()
                            Text(TimeMath.formatHMS(seconds: total.seconds))
                                .font(BrutalistTheme.bodyFont)
                                .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                        }
                    }
                }

                Text("week")
                    .font(BrutalistTheme.labelFont)
                    .foregroundColor(BrutalistTheme.secondary(for: colorScheme))

                HStack(spacing: BrutalistTheme.tightPadding) {
                    Text("total")
                        .font(BrutalistTheme.labelFont)
                        .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
                    Spacer()
                    Text(TimeMath.formatHMS(seconds: weekTotalSeconds()))
                        .font(BrutalistTheme.labelFont)
                        .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                }

                ForEach(appState.weeklyTotals) { total in
                    HStack(spacing: BrutalistTheme.tightPadding) {
                        Text(Self.dayFormatter.string(from: total.date).lowercased())
                            .font(BrutalistTheme.bodyFont)
                            .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
                        Spacer()
                        Text(TimeMath.formatHMS(seconds: total.seconds))
                            .font(BrutalistTheme.labelFont)
                            .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                    }
                }
            }

            SectionDivider()

            VStack(alignment: .leading, spacing: BrutalistTheme.rowSpacing) {
                Text("export")
                    .font(BrutalistTheme.sectionFont)
                    .foregroundColor(BrutalistTheme.foreground(for: colorScheme))

                HStack(spacing: BrutalistTheme.tightPadding) {
                    Text("start")
                        .font(BrutalistTheme.labelFont)
                        .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                    DatePicker("", selection: $exportStart, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .font(BrutalistTheme.bodyFont)
                }

                HStack(spacing: BrutalistTheme.tightPadding) {
                    Text("end")
                        .font(BrutalistTheme.labelFont)
                        .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
                    DatePicker("", selection: $exportEnd, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .font(BrutalistTheme.bodyFont)
                }

                BrutalistTextButton(title: "export csv") {
                    exportCSV()
                }
            }
        }
        .padding(BrutalistTheme.padding)
        .frame(width: 520, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(BrutalistTheme.background(for: colorScheme))
    }

    private func entryTimeLabel(_ entry: TimeEntry) -> String {
        let startText = Self.timeFormatter.string(from: entry.start)
        let endText = entry.end.map { Self.timeFormatter.string(from: $0) } ?? "running"
        return "\(startText) - \(endText)"
    }

    private func beginEdit(_ entry: TimeEntry) {
        editingEntryId = entry.id
        editStart = entry.start
        editEnd = entry.end ?? Date()
        isEndSet = entry.end != nil
        editNote = entry.note ?? ""
    }

    private func clearEdit() {
        editingEntryId = nil
        editNote = ""
        isEndSet = false
    }

    private func resolveEnd(for entry: TimeEntry) -> Date? {
        if isEndSet {
            return editEnd
        }
        if let running = appState.runningEntry, running.id != entry.id {
            return entry.end
        }
        return nil
    }

    private func weekTotalSeconds() -> Int {
        appState.weeklyTotals.reduce(0) { $0 + $1.seconds }
    }

    private func exportCSV() {
        let start = min(exportStart, exportEnd)
        let end = max(exportStart, exportEnd)
        let safeEnd = end <= start ? start.addingTimeInterval(1) : end

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "tt-export-\(dateStamp()).csv"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        if panel.runModal() == .OK, let url = panel.url {
            try? appState.exportCSV(range: start..<safeEnd, to: url)
        }
    }

    private func dateStamp(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }
}
