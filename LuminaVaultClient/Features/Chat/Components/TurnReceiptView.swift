// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/TurnReceiptView.swift
//
// What a turn actually did, under the turn.
//
// The model badge alone answers "who replied". It does not answer the question
// that matters for an agentic product — did it *do* anything? A turn that
// called three tools and a turn that called none looked identical, so the
// work the product does was invisible at exactly the moment a user might have
// been impressed by it.
//
// Deliberately one quiet line rather than a panel. This sits under every
// assistant turn, so it has to earn its space at a glance and never compete
// with the answer above it.
//
// Known limit: on a *live* send the tool count is not available. The server
// counts tool invocations from `ChatStreamChunk.toolCallID`, but nothing in
// `QueryStreamEvent` carries that to the client and `RouterUsageDTO` does not
// include it either — so a freshly streamed turn shows the model alone and
// gains its tool count when the thread is next loaded. Surfacing it live needs
// a new SSE event; inventing a number here would be worse than waiting.

import LuminaVaultShared
import SwiftUI

struct TurnReceiptView: View {
    @Environment(\.lvPalette) private var palette

    let modelLabel: String?
    /// nil means unknown — a turn recorded before the server persisted this.
    /// Zero is a real answer and is rendered as such.
    let toolCallCount: Int?

    var body: some View {
        if let summary {
            Text(summary)
                .font(.caption2)
                .foregroundStyle(palette.textSecondary.opacity(0.7))
                .accessibilityLabel(accessibilityLabel)
        }
    }

    /// `nil` when there is nothing truthful to say — no model and no tool
    /// information. An empty receipt is better than a misleading one.
    private var summary: String? {
        var parts: [String] = []
        if let modelLabel, !modelLabel.isEmpty {
            parts.append(modelLabel)
        }
        if let toolPhrase {
            parts.append(toolPhrase)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Only stated when tools actually ran. "0 tools" under every ordinary
    /// answer would be noise, and would read as a failure rather than as the
    /// normal case.
    private var toolPhrase: String? {
        guard let toolCallCount, toolCallCount > 0 else { return nil }
        return toolCallCount == 1 ? "1 tool" : "\(toolCallCount) tools"
    }

    private var accessibilityLabel: String {
        var label = modelLabel.map { "Answered by \($0)" } ?? "Answered"
        if let toolCallCount, toolCallCount > 0 {
            label += toolCallCount == 1 ? ", using 1 tool" : ", using \(toolCallCount) tools"
        }
        return label
    }
}

extension TurnReceiptView {
    /// The rendered line, exposed for tests. The view itself has no state, so
    /// asserting on the string is asserting on the whole behaviour.
    var summaryForTesting: String? { summary }
    var accessibilityLabelForTesting: String { accessibilityLabel }
}
