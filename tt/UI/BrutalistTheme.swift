import SwiftUI

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >>  8) & 0xff) / 255.0
        let b = Double( hex        & 0xff) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

enum BrutalistTheme {
    // Palette — dark only
    static let bg         = Color(hex: 0x0a0a0a)
    static let fg         = Color(hex: 0xeaeaea)
    static let dim        = Color(hex: 0x666666)
    static let dim2       = Color(hex: 0x888888)
    static let rule       = Color(hex: 0x1d1d1d)
    static let chrome     = Color(hex: 0x1a1a1a)
    static let surface    = Color(hex: 0x141414)
    static let border     = Color(hex: 0x262626)
    static let leader     = Color(hex: 0x2a2a2a)
    static let colonDim   = Color(hex: 0x3a3a3a)
    static let accent     = Color(hex: 0xff4b1f)
    static let danger     = Color(hex: 0xe06464)
    static let dangerHot  = Color(hex: 0xff8080)

    // Font family PostScript names (bundled TTFs)
    static let fontRegular  = "JetBrainsMono-Regular"
    static let fontMedium   = "JetBrainsMono-Medium"
    static let fontSemibold = "JetBrainsMono-SemiBold"

    // Typography — sizes per design handoff
    static let timerMainFont    = Font.custom(fontMedium,   size: 36)
    static let timerPopoverFont = Font.custom(fontMedium,   size: 26)
    static let sectionHeaderFont = Font.custom(fontSemibold, size: 10)
    static let headingFont      = Font.custom(fontSemibold, size: 10)
    static let titleFont        = Font.custom(fontSemibold, size: 13)
    static let bodyFont         = Font.custom(fontRegular,  size: 12)
    static let labelFont        = Font.custom(fontRegular,  size: 10)
    static let buttonFont       = Font.custom(fontRegular,  size: 11)
    static let metaFont         = Font.custom(fontRegular,  size: 10)
    static let captionFont      = Font.custom(fontRegular,  size: 11)
    static let displayFont      = timerMainFont

    // Spacing — compact density
    static let padding: CGFloat            = 20  // horizontal window body padding
    static let paddingTop: CGFloat         = 16
    static let sectionSpacing: CGFloat     = 12  // rule margin
    static let groupSpacing: CGFloat       = 10
    static let rowSpacing: CGFloat         = 6
    static let tightSpacing: CGFloat       = 4
    static let rowVerticalPadding: CGFloat = 2
}

extension BrutalistTheme {
    // Legacy accessors — the `ColorScheme` parameter is ignored now that light
    // mode is dropped. Kept so the currently-committed views keep compiling
    // while the UI phases land.
    static func background(for scheme: ColorScheme) -> Color { bg }
    static func foreground(for scheme: ColorScheme) -> Color { fg }
    static func secondary(for scheme: ColorScheme) -> Color { dim2 }
    static func muted(for scheme: ColorScheme) -> Color { dim }
}

// MARK: - Legacy modifier API

extension View {
    func brutalistHeading(_ scheme: ColorScheme) -> some View {
        self
            .font(BrutalistTheme.headingFont)
            .foregroundColor(BrutalistTheme.fg)
            .textCase(.uppercase)
            .kerning(2.2) // 0.22em at 10pt ≈ 2.2pt
    }

    func brutalistBody(_ scheme: ColorScheme) -> some View {
        self
            .font(BrutalistTheme.bodyFont)
            .foregroundColor(BrutalistTheme.fg)
    }

    func brutalistCaption(_ scheme: ColorScheme) -> some View {
        self
            .font(BrutalistTheme.captionFont)
            .foregroundColor(BrutalistTheme.dim2)
    }

    func brutalistMuted(_ scheme: ColorScheme) -> some View {
        self
            .font(BrutalistTheme.captionFont)
            .foregroundColor(BrutalistTheme.dim)
    }
}

// MARK: - Shared components

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(BrutalistTheme.sectionHeaderFont)
            .foregroundColor(BrutalistTheme.fg)
            .kerning(2.2)
    }
}

struct BrutalistTextButton: View {
    let title: String
    var muted: Bool = false
    var danger: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BrutalistTheme.buttonFont)
                .textCase(.uppercase)
                .kerning(1.5) // 0.14em at 11pt
                .foregroundColor(currentColor)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var currentColor: Color {
        if danger {
            return hovering ? BrutalistTheme.dangerHot : BrutalistTheme.danger
        }
        if hovering {
            return BrutalistTheme.accent
        }
        return muted ? BrutalistTheme.dim : BrutalistTheme.dim2
    }
}

struct BrutalistDivider: View {
    var body: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundColor(BrutalistTheme.rule)
            .padding(.vertical, BrutalistTheme.sectionSpacing)
    }
}

/// A horizontal dotted fill that expands to take available space between two
/// siblings in an `HStack`. Matches the `#2a2a2a` 1px-dotted leader with a
/// -4pt baseline shift from the design handoff.
struct DottedLeader: View {
    var color: Color = BrutalistTheme.leader
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let y = proxy.size.height / 2
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
            }
            .stroke(
                color,
                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 3])
            )
        }
        .frame(height: 1)
        .offset(y: -4)
        .frame(maxWidth: .infinity)
    }
}
