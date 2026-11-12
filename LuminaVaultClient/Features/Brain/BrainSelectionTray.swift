// The selection tray at the bottom of the Brain canvas. A port of the web app's
// `BrainSelectionTray.svelte`, same strings: "N selected", a chip per point
// (kind icon, label, remove), scrolling sideways when they do not fit, and the
// actions from `BrainTrayActions`. An action that does not apply stays put,
// disabled, and says why as its accessibility hint.

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

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            HStack(spacing: LVSpacing.sm) {
                Text("\(nodes.count) selected")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize()
                    .accessibilityIdentifier("brain.tray.count")
                ScrollView(.horizontal) {
                    HStack(spacing: LVSpacing.xs + LVSpacing.hairline) {
                        ForEach(nodes, id: \.id) { node in
                            BrainTrayChip(node: node) { onRemove(node.id) }
                        }
                    }
                    .padding(.vertical, LVSpacing.hairline)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled(false)
                .accessibilityLabel("Selected")
            }
            LVFlowLayout(spacing: LVSpacing.xs + LVSpacing.hairline) {
                ForEach(actions, id: \.id) { action in
                    Button(action.label) { onAction(action.id) }
                        .buttonStyle(.bordered)
                        .tint(action.isEnabled ? palette.primary : nil)
                        .disabled(!action.isEnabled)
                        .accessibilityHint(action.reason ?? "")
                        .accessibilityIdentifier("brain.tray.action.\(Self.key(action.id))")
                }
                Button(action: onClear) {
                    // A bordered button's padding, so Clear lines up with the
                    // actions in the flow layout's top-aligned row.
                    Text("Clear")
                        .padding(.horizontal, LVSpacing.sm + LVSpacing.hairline)
                        .padding(.vertical, LVSpacing.xs + LVSpacing.hairline + 1)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("brain.tray.clear")
            }
            .font(.subheadline)
        }
        .padding(LVSpacing.sm + LVSpacing.hairline)
        .frame(maxWidth: 640, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.surfaceStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, LVSpacing.md)
        .padding(.bottom, LVSpacing.sm)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection")
        .accessibilityIdentifier("brain.tray")
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
/// remove button with a full 44 pt target.
private struct BrainTrayChip: View {
    @Environment(\.lvPalette) private var palette

    let node: BrainGraphNodeDTO
    let onRemove: () -> Void

    var body: some View {
        let kind = BrainSelectionTray.kindName(node.kind)
        HStack(spacing: LVSpacing.xs + LVSpacing.hairline) {
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(node.label) (\(kind))")
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(palette.textSecondary.opacity(0.12)))
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(node.label) (\(kind))")
        }
        .padding(.leading, LVSpacing.sm + LVSpacing.hairline)
        .frame(height: 32)
        .background(Capsule().fill(palette.highlight.opacity(0.12)))
        .overlay(Capsule().strokeBorder(palette.highlight.opacity(0.55), lineWidth: 1))
        .padding(.vertical, LVSpacing.xs + LVSpacing.hairline)
    }
}
