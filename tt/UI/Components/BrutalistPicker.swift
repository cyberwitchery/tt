import SwiftUI

struct BrutalistPicker<T: Identifiable>: View where T.ID: Hashable {
    let items: [T]
    @Binding var selection: T.ID?
    let itemLabel: (T) -> String

    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    private var selectedItem: T? {
        items.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: BrutalistTheme.tightSpacing) {
                    Text(selectedItem.map { itemLabel($0) } ?? "—")
                        .brutalistBody(colorScheme)
                    Text(isExpanded ? "▴" : "▾")
                        .brutalistMuted(colorScheme)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        Button(action: {
                            selection = item.id
                            isExpanded = false
                        }) {
                            Text(itemLabel(item))
                                .font(BrutalistTheme.bodyFont)
                                .foregroundColor(
                                    item.id == selection
                                        ? BrutalistTheme.foreground(for: colorScheme)
                                        : BrutalistTheme.secondary(for: colorScheme)
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, BrutalistTheme.tightSpacing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, BrutalistTheme.tightSpacing)
            }
        }
    }
}
