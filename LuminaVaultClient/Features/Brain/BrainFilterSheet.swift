// The Brain screen's filters, in a medium-detent sheet. Every control except
// the vault chips and the depth stepper filters the graph on screen in place;
// a vault chip or a depth step changes the request, which the store fetches
// once. The connection dots are the legend: the same `theme.link(kind)`
// colours the canvas draws edges in.

import LuminaVaultShared
import SwiftUI

struct BrainFilterSheet: View {
    @Binding var filters: BrainGraphFilters
    @Binding var depth: Int
    let focus: String?
    let knownVaults: [BrainGraphVaultDTO]
    /// The visible keys of the current colour, commonest first.
    let legend: (keys: [BrainLegendKey], more: Int)
    let noSimilarFound: Bool
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    /// Legend dots grow with the text beside them.
    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 12

    private var theme: BrainGraphTheme { BrainGraphTheme(palette: palette, scheme: scheme) }
    private var authorsUnavailable: Bool { BrainTabState.authorsUnavailable(focus: focus) }

    var body: some View {
        let theme = theme
        NavigationStack {
            Form {
                // Vaults first: the one setting that asks the server again.
                if knownVaults.count > 1 { vaults(theme) }
                connections(theme)
                colourBy(theme)
                Section {
                    Toggle("Show unlinked notes", isOn: $filters.showOrphans)
                        .accessibilityIdentifier("brain.filter.orphans")
                    if focus != nil {
                        Stepper(value: $depth, in: 1 ... 3) {
                            Text(depth == 1 ? "1 step from the focus" : "\(depth) steps from the focus")
                        }
                        .disabled(BrainGraphRequest.isAuthorFocus(focus))
                    }
                }
                Section {
                    Button(BrainTabState.resetTitle, role: .destructive, action: onReset)
                        .disabled(BrainTabState.badgeCount(filters) == 0)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("brain.sheet.done")
                }
            }
        }
    }

    // MARK: Sections

    private func connections(_ theme: BrainGraphTheme) -> some View {
        Section("Connections") {
            ForEach(BrainLinkKindDTO.allCases, id: \.self) { kind in
                let off = kind == .author && authorsUnavailable
                VStack(alignment: .leading, spacing: LVSpacing.xs) {
                    Toggle(isOn: linkBinding(kind)) {
                        Label {
                            Text(BrainGraphCopy.linkLabel(kind))
                        } icon: {
                            Circle()
                                .fill(theme.link(kind))
                                .frame(width: dot, height: dot)
                        }
                    }
                    .disabled(off)
                    .accessibilityIdentifier("brain.filter.link.\(kind.rawValue)")
                    if off {
                        footnote(BrainTabState.notShownInFocusText)
                    } else if kind == .similar, noSimilarFound {
                        footnote(BrainTabState.noSimilarText)
                    }
                }
            }
        }
    }

    private func vaults(_ theme: BrainGraphTheme) -> some View {
        let known = knownVaults.map(\.id)
        let order = known.map(\.uuidString)
        return Section("Vaults") {
            BrainChipFlow(spacing: LVSpacing.sm) {
                ForEach(knownVaults) { vault in
                    let on = BrainTabState.isVaultOn(vault.id, in: filters.vaults)
                    Button {
                        filters.vaults = BrainTabState.toggledVault(vault.id, in: filters.vaults, known: known)
                    } label: {
                        HStack(spacing: LVSpacing.xs) {
                            Circle()
                                .fill(theme.categoryColour(for: vault.id.uuidString, order: order))
                                .frame(width: dot * 0.85, height: dot * 0.85)
                            Text(vault.name)
                            if on { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                        }
                        .frame(minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(on ? palette.primary : palette.textSecondary)
                    .disabled(!BrainTabState.canToggleVault(vault.id, in: filters.vaults, known: known))
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("brain.filter.vault.\(vault.name)")
                }
            }
            .padding(.vertical, LVSpacing.xs)
        }
    }

    private func colourBy(_ theme: BrainGraphTheme) -> some View {
        Section("Colour by") {
            ForEach(BrainColourBy.allCases, id: \.self) { by in
                let off = by == .author && authorsUnavailable
                Button {
                    filters.colourBy = by
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: LVSpacing.hairline) {
                            Text(Self.colourByName(by))
                                .foregroundStyle(off ? palette.textSecondary : palette.textPrimary)
                            if off { footnote(BrainTabState.notShownInFocusText) }
                        }
                        Spacer()
                        if filters.colourBy == by {
                            Image(systemName: "checkmark")
                                .foregroundStyle(palette.primary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .disabled(off)
                .accessibilityAddTraits(filters.colourBy == by ? .isSelected : [])
            }
            if filters.colourBy != .vault {
                ForEach(legend.keys, id: \.key) { key in
                    HStack(spacing: LVSpacing.sm) {
                        Circle()
                            .fill(theme.categoryColour(for: key.key, order: legend.keys.map(\.key)))
                            .frame(width: dot * 0.85, height: dot * 0.85)
                        Text(key.label)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("\(key.count)")
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
                if legend.more > 0 {
                    footnote("and \(legend.more) more")
                }
            }
        }
    }

    // MARK: Pieces

    private func linkBinding(_ kind: BrainLinkKindDTO) -> Binding<Bool> {
        Binding(
            get: { filters.links[kind] ?? false },
            set: { filters.links[kind] = $0 }
        )
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(palette.textSecondary)
    }

    static func colourByName(_ by: BrainColourBy) -> String {
        switch by {
        case .vault: "Vault"
        case .space: "Space"
        case .author: "Author"
        case .kind: "Type"
        }
    }
}

/// Chips that wrap onto as many lines as they need.
private struct BrainChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
                x += min(size.width, bounds.width) + spacing
            }
        }
    }

    private struct Row {
        var items: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let w = min(size.width, width)
            if !row.items.isEmpty, row.width + spacing + w > width {
                let y = row.y + row.height + spacing
                rows.append(row)
                row = Row(y: y)
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + w
            row.height = max(row.height, size.height)
            row.items.append(index)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
