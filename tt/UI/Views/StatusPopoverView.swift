import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var appState: AppState
    @State private var pickerOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let error = appState.storageError {
                Text(error).font(BrutalistTheme.metaFont).foregroundColor(BrutalistTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            projectRow
                .disabled(!appState.isStorageAvailable)
                .zIndex(10) // dropdown floats above timer/footer
            timerRow
                .disabled(!appState.isStorageAvailable)
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
                .trackerLabel(font: BrutalistTheme.metaFont, color: BrutalistTheme.dim, kerning: 1.3)
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
                Text("started \(TrackerText.date(started, label: .time, days: appState.days))")
                    .trackerLabel(font: BrutalistTheme.metaFont, color: BrutalistTheme.dim, kerning: 1.1)
            }
        }
    }

    private var timerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(TrackerText.timer(seconds: appState.elapsedSeconds))
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
                    .trackerLabel(font: BrutalistTheme.metaFont, color: BrutalistTheme.dim, kerning: 1.1)
                Text(TimeMath.formatHM(seconds: appState.todayTotalSeconds()))
                    .font(BrutalistTheme.metaFont)
                    .foregroundColor(BrutalistTheme.fg)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                Text("last 7d")
                    .trackerLabel(font: BrutalistTheme.metaFont, color: BrutalistTheme.dim, kerning: 1.1)
                Text(TimeMath.formatHM(seconds: appState.recentTotalSeconds()))
                    .font(BrutalistTheme.metaFont)
                    .foregroundColor(BrutalistTheme.fg)
                    .monospacedDigit()
            }
            Spacer()
        }
    }

}
