import SwiftUI

struct COCOMOSectionView: View {
    @ObservedObject var appState: AppState

    @State private var slocText = ""
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrutalistTheme.groupSpacing) {
            SectionHeader(title: "estimate")

            if let params = appState.cocomoParams {
                slocRow(params)
                resultRow(params)

                if expanded {
                    scaleFactorsGroup(params)
                    effortMultipliersSection(params)
                }

                expandToggle
            } else {
                Text("select a project")
                    .font(BrutalistTheme.bodyFont)
                    .foregroundColor(BrutalistTheme.dim)
            }
        }
    }

    // MARK: - SLOC Input

    private func slocRow(_ params: COCOMOParams) -> some View {
        HStack(spacing: 8) {
            Text("sloc")
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.dim2)
            TextField("0", text: $slocText)
                .textFieldStyle(.plain)
                .font(BrutalistTheme.bodyFont)
                .foregroundColor(BrutalistTheme.fg)
                .monospacedDigit()
                .frame(width: 80)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(BrutalistTheme.border)
                }
                .onSubmit { commitSloc(params) }
            Spacer()
        }
        .onAppear { slocText = params.sloc > 0 ? String(params.sloc) : "" }
        .onChange(of: params.projectId) { _ in
            slocText = params.sloc > 0 ? String(params.sloc) : ""
        }
    }

    private func commitSloc(_ params: COCOMOParams) {
        let value = Int(slocText.trimmingCharacters(in: .whitespaces)) ?? 0
        var updated = params
        updated.sloc = max(0, value)
        appState.updateCOCOMOParams(updated)
        slocText = updated.sloc > 0 ? String(updated.sloc) : ""
    }

    // MARK: - Result

    private func resultRow(_ params: COCOMOParams) -> some View {
        let result = params.estimate()
        let actualSeconds = appState.projectAllTimeSeconds(for: params.projectId)
        let actualHours = Double(actualSeconds) / 3600.0

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("estimated")
                    .font(BrutalistTheme.bodyFont)
                    .foregroundColor(BrutalistTheme.dim2)
                DottedLeader()
                if params.sloc > 0 {
                    Text(formatEstimate(result))
                        .font(BrutalistTheme.bodyFont)
                        .foregroundColor(BrutalistTheme.fg)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(BrutalistTheme.bodyFont)
                        .foregroundColor(BrutalistTheme.dim)
                }
            }

            HStack(spacing: 8) {
                Text("tracked")
                    .font(BrutalistTheme.bodyFont)
                    .foregroundColor(BrutalistTheme.dim2)
                DottedLeader()
                Text(HMS.hoursMinutes(actualSeconds))
                    .font(BrutalistTheme.bodyFont)
                    .foregroundColor(BrutalistTheme.fg)
                    .monospacedDigit()
            }

            if params.sloc > 0 && result.hours > 0 && actualHours > 0 {
                let ratio = actualHours / result.hours
                HStack(spacing: 8) {
                    Text("ratio")
                        .font(BrutalistTheme.bodyFont)
                        .foregroundColor(BrutalistTheme.dim2)
                    DottedLeader()
                    Text(String(format: "%.0f%%", ratio * 100))
                        .font(BrutalistTheme.bodyFont)
                        .foregroundColor(ratioColor(ratio))
                        .monospacedDigit()
                }
            }
        }
    }

    private func formatEstimate(_ result: COCOMOResult) -> String {
        let hours = Int(result.hours.rounded())
        if result.personMonths >= 1.0 {
            return String(format: "%.1f PM · %@", result.personMonths, HMS.hoursMinutes(hours * 3600))
        }
        return HMS.hoursMinutes(hours * 3600)
    }

    private func ratioColor(_ ratio: Double) -> Color {
        if ratio < 0.8 || ratio > 1.2 {
            return BrutalistTheme.accent
        }
        return BrutalistTheme.fg
    }

    // MARK: - Scale Factors

    private func scaleFactorsGroup(_ params: COCOMOParams) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SCALE FACTORS")
                .font(BrutalistTheme.labelFont)
                .foregroundColor(BrutalistTheme.dim)
                .kerning(1.5)
                .padding(.top, 4)

            ForEach(ScaleFactor.allCases, id: \.rawValue) { sf in
                ratingRow(
                    label: sf.label,
                    rating: params.scaleFactorRating(sf),
                    onSelect: { rating in
                        var updated = params
                        updated.setScaleFactor(sf, to: rating)
                        appState.updateCOCOMOParams(updated)
                    }
                )
            }
        }
    }

    // MARK: - Effort Multipliers

    private func effortMultipliersSection(_ params: COCOMOParams) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(EffortMultiplierGroup.allCases, id: \.rawValue) { group in
                effortMultiplierGroup(group, params: params)
            }
        }
    }

    private func effortMultiplierGroup(_ group: EffortMultiplierGroup, params: COCOMOParams) -> some View {
        let multipliers = EffortMultiplier.allCases.filter { $0.group == group }
        return VStack(alignment: .leading, spacing: 4) {
            Text(group.rawValue.uppercased())
                .font(BrutalistTheme.labelFont)
                .foregroundColor(BrutalistTheme.dim)
                .kerning(1.5)
                .padding(.top, 4)

            ForEach(multipliers, id: \.rawValue) { em in
                ratingRow(
                    label: em.label,
                    rating: params.effortMultiplierRating(em),
                    onSelect: { rating in
                        var updated = params
                        updated.setEffortMultiplier(em, to: rating)
                        appState.updateCOCOMOParams(updated)
                    }
                )
            }
        }
    }

    // MARK: - Rating Picker Row

    private func ratingRow(label: String, rating: COCOMORating, onSelect: @escaping (COCOMORating) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label.lowercased())
                .font(BrutalistTheme.metaFont)
                .foregroundColor(BrutalistTheme.dim2)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)

            ForEach(COCOMORating.allCases, id: \.rawValue) { r in
                Button(action: { onSelect(r) }) {
                    Text(r.label)
                        .font(.system(size: 9, weight: r == rating ? .bold : .regular, design: .monospaced))
                        .foregroundColor(r == rating ? BrutalistTheme.accent : BrutalistTheme.dim)
                        .frame(width: 22)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.vertical, 1)
    }

    // MARK: - Expand Toggle

    private var expandToggle: some View {
        BrutalistTextButton(title: expanded ? "hide params ▴" : "params ▾", muted: true) {
            expanded.toggle()
        }
    }
}
