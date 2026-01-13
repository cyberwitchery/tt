import SwiftUI

struct SectionDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("* * *")
            .font(BrutalistTheme.labelFont)
            .foregroundColor(BrutalistTheme.secondary(for: colorScheme))
            .padding(.top, BrutalistTheme.dividerTopPadding)
            .padding(.bottom, BrutalistTheme.dividerBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
