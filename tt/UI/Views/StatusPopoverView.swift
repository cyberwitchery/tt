import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.sectionSpacing) {
            HStack(spacing: BrutalistTheme.tightPadding) {
                Text("tt")
                    .font(BrutalistTheme.titleFont)
                    .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
                Spacer()
                BrutalistTextButton(title: "open") {
                    NotificationCenter.default.post(name: .ttShowMainWindow, object: nil)
                    NotificationCenter.default.post(name: .ttHidePanel, object: nil)
                }
                BrutalistTextButton(title: "quit") {
                    NotificationCenter.default.post(name: .ttRequestQuit, object: nil)
                }
            }

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
        }
        .padding(.horizontal, BrutalistTheme.padding)
        .padding(.bottom, BrutalistTheme.padding)
        .padding(.top, BrutalistTheme.tightPadding)
        .frame(width: 300)
        .background(BrutalistTheme.background(for: colorScheme))
    }
}
