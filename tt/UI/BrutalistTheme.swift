import SwiftUI

enum BrutalistTheme {
    // Colors
    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black : Color.white
    }

    static func foreground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white : Color.black
    }

    static func secondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.5) : Color(white: 0.4)
    }

    static func muted(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.35) : Color(white: 0.55)
    }

    // Typography - clear hierarchy
    static let displayFont = Font.system(size: 25, weight: .regular, design: .monospaced)
    static let titleFont = Font.system(size: 14, weight: .bold, design: .monospaced)
    static let headingFont = Font.system(size: 12, weight: .bold, design: .monospaced)
    static let bodyFont = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let captionFont = Font.system(size: 11, weight: .regular, design: .monospaced)

    // Spacing
    static let padding: CGFloat = 12
    static let sectionSpacing: CGFloat = 20
    static let groupSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 6
    static let tightSpacing: CGFloat = 4
}

// MARK: - View Modifiers

extension View {
    func brutalistHeading(_ scheme: ColorScheme) -> some View {
        self
            .font(BrutalistTheme.headingFont)
            .foregroundColor(BrutalistTheme.foreground(for: scheme))
    }

    func brutalistBody(_ scheme: ColorScheme) -> some View {
        self
            .font(BrutalistTheme.bodyFont)
            .foregroundColor(BrutalistTheme.foreground(for: scheme))
    }

    func brutalistCaption(_ scheme: ColorScheme) -> some View {
        self
            .font(BrutalistTheme.captionFont)
            .foregroundColor(BrutalistTheme.secondary(for: scheme))
    }

    func brutalistMuted(_ scheme: ColorScheme) -> some View {
        self
            .font(BrutalistTheme.captionFont)
            .foregroundColor(BrutalistTheme.muted(for: scheme))
    }
}

// MARK: - Components

struct SectionHeader: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title.uppercased())
            .font(BrutalistTheme.headingFont)
            .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
            .kerning(1)
    }
}

struct BrutalistTextButton: View {
    let title: String
    var muted: Bool = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BrutalistTheme.captionFont)
                .foregroundColor(muted
                    ? BrutalistTheme.muted(for: colorScheme)
                    : BrutalistTheme.secondary(for: colorScheme))
        }
        .buttonStyle(.plain)
    }
}

struct BrutalistDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundColor(BrutalistTheme.muted(for: colorScheme))
            .padding(.vertical, BrutalistTheme.rowSpacing)
    }
}
