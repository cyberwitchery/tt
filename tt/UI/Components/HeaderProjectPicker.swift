import SwiftUI

/// Tappable project label with a floating dropdown of all projects (with
/// all-time totals) and a `+ new project` option at the bottom. Used in the
/// main-window header and the status popover.
struct HeaderProjectPicker: View {
    let projects: [Project]
    @Binding var selectedId: String?
    let allTimeSeconds: (String) -> Int
    let onCreateProject: (String) -> Void
    @Binding var isOpen: Bool

    @State private var adding: Bool = false
    @State private var newName: String = ""
    @FocusState private var addFocused: Bool

    private var selectedName: String {
        projects.first { $0.id == selectedId }?.name.lowercased() ?? "—"
    }

    var body: some View {
        HStack(spacing: BrutalistTheme.tightSpacing) {
            Text(selectedName)
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.fg)
            Text(isOpen ? "▴" : "▾")
                .font(BrutalistTheme.metaFont)
                .foregroundColor(BrutalistTheme.dim)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isOpen.toggle()
            if !isOpen { adding = false; newName = "" }
        }
        .overlay(alignment: .topLeading) {
            if isOpen {
                dropdown
                    .offset(y: 22)
                    .zIndex(100)
            }
        }
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(projects) { project in
                Button(action: {
                    selectedId = project.id
                    isOpen = false
                }) {
                    HStack {
                        Text(project.name.lowercased())
                            .font(BrutalistTheme.bodyFont)
                            .foregroundColor(project.id == selectedId
                                ? BrutalistTheme.accent
                                : BrutalistTheme.fg)
                        Spacer()
                        Text(HMS.hoursMinutes(allTimeSeconds(project.id)))
                            .font(BrutalistTheme.metaFont)
                            .foregroundColor(BrutalistTheme.dim)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .frame(height: 1)
                .foregroundColor(BrutalistTheme.border)

            if adding {
                addRow
            } else {
                Button(action: {
                    adding = true
                    addFocused = true
                }) {
                    HStack(spacing: 6) {
                        Text("+")
                            .font(BrutalistTheme.bodyFont)
                            .foregroundColor(BrutalistTheme.accent)
                        Text("new project")
                            .font(BrutalistTheme.bodyFont)
                            .italic()
                            .foregroundColor(BrutalistTheme.dim2)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 200, alignment: .leading)
        .background(BrutalistTheme.surface)
        .overlay(
            Rectangle()
                .strokeBorder(BrutalistTheme.border, lineWidth: 1)
        )
    }

    private var addRow: some View {
        HStack(spacing: 6) {
            Text("+")
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.accent)
            TextField("project name…", text: $newName)
                .textFieldStyle(.plain)
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.fg)
                .focused($addFocused)
                .onSubmit(commitAdd)
            Text("⏎ add · esc cancel")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(BrutalistTheme.dim)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .onExitCommand(perform: cancelAdd)
    }

    private func commitAdd() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreateProject(trimmed)
        cancelAdd()
        isOpen = false
    }

    private func cancelAdd() {
        adding = false
        newName = ""
        addFocused = false
    }
}

/// Shared HH:MM / HH:MM:SS helpers for the UI layer. Kept here so multiple
/// components can share formatting logic without importing `TimeMath`
/// indirectly.
enum HMS {
    /// `HHHH:MM` (unpadded hours when large, zero-padded otherwise). No seconds.
    static func hoursMinutes(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        if h >= 100 {
            return String(format: "%d:%02d", h, m)
        }
        return String(format: "%02d:%02d", h, m)
    }

    /// `HH:MM:SS`, timer-style. Hours unpadded when >= 1000 per spec.
    static func hoursMinutesSeconds(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        if h >= 1000 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// `H:MM` with unpadded hours (for `idle 0:04`, `idle 12:30`).
    static func idleHours(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }
}
