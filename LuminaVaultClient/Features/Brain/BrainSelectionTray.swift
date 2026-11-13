// The selection tray at the bottom of the Brain canvas. A port of the web app's
// `BrainSelectionTray.svelte`, same strings: "N selected", a chip per point
// (kind icon, label, remove), scrolling sideways when they do not fit, and the
// actions from `BrainTrayActions`. An action that does not apply stays put,
// disabled, and says why as its accessibility hint.
//
// It is a bar, not a card: the caller lays it over the bottom edge of the
// graph (an overlay, so the graph never resizes when it comes and goes), and it
// draws `.bar` behind itself so it reads as part of the bottom chrome
// (DESIGN_SYSTEM §13.5). Every control has a 44 × 44 pt target.

import LuminaVaultShared
import SwiftUI

struct BrainSelectionTray: View {
    @Environment(\.lvPalette) private var palette

    /// The selected points, in the order they were picked.
    let nodes: [BrainGraphNodeDTO]
    let actions: [BrainTrayAction]
    let onRemove: (String) -> Void
    let onClear: () -> Void
    let onAction: (BrainTrayActionID) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            if typeSize.isAccessibilitySize {
                // Large type: the chips get the whole width, and the actions
                // scroll sideways instead of wrapping over the graph.
                HStack {
                    count
                    Spacer(minLength: LVSpacing.sm)
                    clear
                }
                chips
                ScrollView(.horizontal) {
                    HStack(spacing: LVSpacing.sm) { actionButtons }
                }
                .scrollIndicators(.hidden)
            } else {
                HStack(spacing: LVSpacing.sm) {
                    count
                    chips
                    clear
                }
                LVFlowLayout(spacing: LVSpacing.sm) { actionButtons }
            }
        }
        .font(.subheadline)
        .padding(.horizontal, LVSpacing.base)
        .padding(.top, LVSpacing.xs)
        .padding(.bottom, LVSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection")
        .accessibilityIdentifier("brain.tray")
    }

    private var count: some View {
        Text("\(nodes.count) selected")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(palette.textSecondary)
            .fixedSize()
            .accessibilityIdentifier("brain.tray.count")
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            // Lazy: "Select group" on a large hub selects up to 800 points.
            LazyHStack(spacing: LVSpacing.xs) {
                ForEach(nodes, id: \.id) { node in
                    BrainTrayChip(node: node) { onRemove(node.id) }
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Selected")
    }

    private var clear: some View {
        Button(action: onClear) {
            Text("Clear")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("brain.tray.clear")
    }

    private var actionButtons: some View {
        ForEach(actions, id: \.id) { action in
            Button(action.label) { onAction(action.id) }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!action.isEnabled)
                .accessibilityHint(action.reason ?? "")
                .accessibilityIdentifier("brain.tray.action.\(Self.key(action.id))")
        }
    }

    static func key(_ id: BrainTrayActionID) -> String {
        switch id {
        case .open: "open"
        case .focus: "focus"
        case .group: "group"
        case .explain: "explain"
        case .ask: "ask"
        }
    }

    static func kindName(_ kind: BrainNodeKindDTO) -> String {
        switch kind {
        case .note: "Note"
        case .memory: "Memory"
        case .tag: "Tag"
        case .author: "Author"
        case .entity: "Mention"
        case .space: "Space"
        }
    }

    static func kindIcon(_ kind: BrainNodeKindDTO) -> String {
        switch kind {
        case .note: "doc.text"
        case .memory: "bookmark"
        case .tag: "number"
        case .author: "person"
        case .entity: "at"
        case .space: "square.grid.2x2"
        }
    }
}

/// One selected point: kind icon, its label cut to 24 characters, and a
/// remove button. The capsule is drawn inside the 44 pt row the remove
/// button's target sets, and grows with the text at large type sizes.
private struct BrainTrayChip: View {
    @Environment(\.lvPalette) private var palette

    let node: BrainGraphNodeDTO
    let onRemove: () -> Void

    var body: some View {
        let kind = BrainSelectionTray.kindName(node.kind)
        HStack(spacing: 0) {
            HStack(spacing: LVSpacing.xs + LVSpacing.hairline) {
                // Runtime symbol name per kind.
                Image(systemName: BrainSelectionTray.kindIcon(node.kind))
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                Text(BrainTrayActions.chipLabel(node.label))
                    .font(.footnote)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.vertical, LVSpacing.xs)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(node.label) (\(kind))")
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(node.label) (\(kind))")
        }
        .padding(.leading, LVSpacing.sm + LVSpacing.hairline)
        .frame(minHeight: 44)
        .background {
            Capsule()
                .fill(palette.surfaceElevated)
                .overlay(Capsule().strokeBorder(palette.highlight.opacity(0.55), lineWidth: 1))
                .padding(.vertical, LVSpacing.xs + LVSpacing.hairline)
                .padding(.trailing, LVSpacing.xs)
        }
    }
}
