import SwiftUI

/// `#141414` bg + 1px `#262626` hairline border — used for the inline editor,
/// add-row, confirm, chip, and picker-menu surfaces.
struct SurfaceStyle: ViewModifier {
    var verticalPadding: CGFloat
    var horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background(BrutalistTheme.surface)
            .overlay(
                Rectangle()
                    .strokeBorder(BrutalistTheme.border, lineWidth: 1)
            )
    }
}

extension View {
    func brutalistSurface(vertical: CGFloat = 8, horizontal: CGFloat = 12) -> some View {
        modifier(SurfaceStyle(verticalPadding: vertical, horizontalPadding: horizontal))
    }
}
