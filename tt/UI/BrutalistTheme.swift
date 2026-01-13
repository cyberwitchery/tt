import SwiftUI

enum BrutalistTheme {
    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black : Color.white
    }

    static func foreground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white : Color.black
    }

    static func secondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.7) : Color.gray
    }

    static let titleFont = Font.system(size: 13, weight: .bold, design: .monospaced)
    static let sectionFont = Font.system(size: 12, weight: .semibold, design: .monospaced)
    static let bodyFont = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let labelFont = Font.system(size: 11, weight: .regular, design: .monospaced)

    static let padding: CGFloat = 8
    static let sectionSpacing: CGFloat = 14
    static let rowSpacing: CGFloat = 6
    static let tightPadding: CGFloat = 4
    static let dividerTopPadding: CGFloat = 0
    static let dividerBottomPadding: CGFloat = 10
}

struct BrutalistTextButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BrutalistTheme.labelFont)
                .foregroundColor(BrutalistTheme.foreground(for: colorScheme))
        }
        .buttonStyle(.plain)
    }
}
