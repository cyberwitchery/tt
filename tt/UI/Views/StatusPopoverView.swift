import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var appState: AppState
    @State private var pickerOpen = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            projectRow
                .zIndex(10) // dropdown floats above timer/footer
            timerRow
            Rectangle()
                .frame(height: 1)
                .foregroundColor(BrutalistTheme.rule)
                .padding(.vertical, 2)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BrutalistTheme.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(BrutalistTheme.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text("tt")
                .font(BrutalistTheme.titleFont)
                .foregroundColor(BrutalistTheme.fg)
            Spacer()
            HStack(spacing: 10) {
                BrutalistTextButton(title: "open", muted: true) {
                    NotificationCenter.default.post(name: .ttShowMainWindow, object: nil)
                    NotificationCenter.default.post(name: .ttHidePanel, object: nil)
                }
                BrutalistTextButton(title: "quit", muted: true) {
                    NotificationCenter.default.post(name: .ttRequestQuit, object: nil)
                }
            }
        }
    }

    private var projectRow: some View {
        HStack(spacing: 6) {
            Text("project")
                .font(BrutalistTheme.metaFont)
                .foregroundColor(BrutalistTheme.dim)
                .textCase(.uppercase)
                .kerning(1.3)
            HeaderProjectPicker(
                projects: appState.projects,
                selectedId: Binding(
                    get: { appState.selectedProjectId },
                    set: { if let id = $0 { appState.selectProject(id: id) } }
                ),
                allTimeSeconds: { appState.projectAllTimeSeconds(for: $0) },
                onCreateProject: { appState.createProject(name: $0) },
                isOpen: $pickerOpen
            )
            Spacer()
            if let started = appState.startedAt {
                Text("started \(Self.timeFormatter.string(from: started))")
                    .font(BrutalistTheme.metaFont)
                    .foregroundColor(BrutalistTheme.dim)
                    .textCase(.uppercase)
                    .kerning(1.1)
            }
        }
    }

    private var timerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(colorizeTimer(HMS.hoursMinutesSeconds(appState.elapsedSeconds)))
                .font(BrutalistTheme.timerPopoverFont)
                .kerning(-0.2)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
            Spacer()
            if appState.runningEntry == nil {
                BrutalistTextButton(title: "start ▶") { appState.startTimer() }
            } else {
                BrutalistTextButton(title: "stop ■") { appState.stopTimer() }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("today")
                    .font(BrutalistTheme.metaFont)
                    .foregroundColor(BrutalistTheme.dim)
                    .textCase(.uppercase)
                    .kerning(1.1)
                Text(HMS.hoursMinutes(todaySeconds()))
                    .font(BrutalistTheme.metaFont)
                    .foregroundColor(BrutalistTheme.fg)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                Text("week")
                    .font(BrutalistTheme.metaFont)
                    .foregroundColor(BrutalistTheme.dim)
                    .textCase(.uppercase)
                    .kerning(1.1)
                Text(HMS.hoursMinutes(weekSeconds()))
                    .font(BrutalistTheme.metaFont)
                    .foregroundColor(BrutalistTheme.fg)
                    .monospacedDigit()
            }
            Spacer()
        }
    }

    private func todaySeconds() -> Int {
        appState.todaysEntries.reduce(0) { sum, e in
            sum + TimeMath.durationSeconds(start: e.start, end: e.end)
        }
    }

    private func weekSeconds() -> Int {
        appState.weeklyTotals.reduce(0) { $0 + $1.seconds }
    }

    private func colorizeTimer(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.foregroundColor = BrutalistTheme.fg
        var search = attr.startIndex
        while let range = attr[search...].range(of: ":") {
            attr[range].foregroundColor = BrutalistTheme.colonDim
            search = range.upperBound
        }
        return attr
    }
}
