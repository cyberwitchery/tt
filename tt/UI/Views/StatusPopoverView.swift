import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.groupSpacing) {
            // Header
            HStack {
                Text("tt")
                    .font(BrutalistTheme.titleFont)
                    .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
                Spacer()
                BrutalistTextButton(title: "open", muted: true) {
                    NotificationCenter.default.post(name: .ttShowMainWindow, object: nil)
                    NotificationCenter.default.post(name: .ttHidePanel, object: nil)
                }
                BrutalistTextButton(title: "quit", muted: true) {
                    NotificationCenter.default.post(name: .ttRequestQuit, object: nil)
                }
            }

            // Project
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

            // Timer
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
        .padding(BrutalistTheme.padding)
        .frame(width: 280)
        .background(BrutalistTheme.background(for: colorScheme))
    }
}
