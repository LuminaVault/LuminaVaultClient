// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ChatToolTrailView.swift
//
// What the agent did on an escalated turn, inline in the transcript.
//
// Collapsed while the run works, because a trail that grows under the reader
// pushes the answer around exactly when they are trying to read it. Expanded
// once it settles, when the steps are what there is to read.
//
// Rows come from `HermesRunTrailItem`, the same mapper the Agent Runs screen
// uses, so a step reads identically in both places.

import LuminaVaultShared
import SwiftUI

struct ChatToolTrailView: View {
    let items: [HermesRunTrailItem]
    let isRunning: Bool
    /// Tools the run actually invoked, from `ChatRunFollower.toolCallCount`.
    /// Not derived from `items`: a start and its completion are both `.tool`
    /// rows, so counting rows reported every call twice.
    let toolCount: Int
    /// Opens a step in the preview pane. Tap only — nothing here opens it on
    /// its own. `nil` hides the affordance.
    var onSelect: ((HermesRunTrailItem) -> Void)?

    @Environment(\.lvPalette) private var palette
    @State private var isExpanded = false
    @State private var userToggled = false

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                header
                if isExpanded {
                    VStack(alignment: .leading, spacing: LVSpacing.xs) {
                        ForEach(items) { item in
                            if let onSelect, item.kind == .tool || item.kind == .failure {
                                Button {
                                    onSelect(item)
                                } label: {
                                    row(item).contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Shows this step's output")
                            } else {
                                row(item)
                            }
                        }
                    }
                }
            }
            .padding(LVSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                    .fill(palette.surface)
            )
            .onChange(of: isRunning) { _, running in
                // Open it once the work is done, unless the reader already
                // made that choice themselves.
                if !running, !userToggled { isExpanded = true }
            }
        }
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
            userToggled = true
        } label: {
            HStack(spacing: LVSpacing.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Text(isRunning ? "Working" : "Agent activity")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(1.2)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: LVSpacing.sm)
                if !isExpanded, let latest = items.last {
                    Text(latest.title)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("\(toolCount) \(toolCount == 1 ? "tool" : "tools")")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Agent activity, \(toolCount) tools")
        .accessibilityHint(isExpanded ? "Collapses the step list" : "Expands the step list")
    }

    private func row(_ item: HermesRunTrailItem) -> some View {
        HStack(alignment: .top, spacing: LVSpacing.sm) {
            Image(systemName: item.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(item.kind == .failure ? Color.red : palette.textSecondary)
                .frame(width: 14, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption)
                    .foregroundStyle(palette.textPrimary)
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
