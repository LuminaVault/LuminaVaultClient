// LuminaVaultClient/LuminaVaultClient/Features/Settings/Components/AgentStatusRow.swift
//
// Which brain is answering, and whether it is up.
//
// This replaces the Dashboard's agent-core status panel. The information was
// worth keeping and the theatre was not, and Settings is where someone goes
// when they want to know what their agent is set to.

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class AgentStatusRowViewModel {
    /// Three states, not two. "Offline" is something the server told us; a
    /// request that never landed knows nothing, and saying "Offline" for it
    /// asserts a fact we do not have.
    enum Status {
        case unknown
        case online
        case offline
    }

    private(set) var model: String?
    private(set) var provider: String?
    private(set) var status: Status = .unknown
    private(set) var loaded = false

    private let client: any HomeSummaryClientProtocol

    init(client: any HomeSummaryClientProtocol) {
        self.client = client
    }

    /// One call on appear. Settings is not a monitor, so nothing polls.
    func load() async {
        guard !loaded else { return }
        do {
            let summary = try await client.summary(period: .today)
            model = summary.primaryModel
            provider = summary.primaryProvider
            status = summary.agentOnline ? .online : .offline
            loaded = true
        } catch {
            // The row shows the default-brain copy and "Status unavailable"
            // rather than inventing a model name or asserting Offline, and
            // stays unloaded so a later appearance retries.
            status = .unknown
            loaded = false
        }
    }
}

/// Read-only sibling of `LVSettingsRow` — same metrics, no destination.
struct AgentStatusRow: View {
    @Environment(\.lvPalette) private var palette
    @State private var vm: AgentStatusRowViewModel

    init(client: any HomeSummaryClientProtocol) {
        _vm = State(initialValue: AgentStatusRowViewModel(client: client))
    }

    var body: some View {
        HStack(spacing: LVSpacing.base) {
            LVIconView(.brainHeadProfile, size: 18, tint: palette.glowPrimary, weight: .medium)
                .frame(width: LVSize.rowGlyph)

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.model ?? "Default brain")
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                if let provider = vm.provider, !provider.isEmpty {
                    Text(provider)
                        .lvFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: LVSpacing.sm)

            HStack(spacing: LVSpacing.xs) {
                // No dot when the status is unknown: a grey dot reads as a
                // reported state, and nothing was reported.
                if let tone = dotTone {
                    Circle()
                        .fill(tone)
                        .frame(width: 8, height: 8)
                }
                Text(statusText)
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.vertical, LVSpacing.md)
        .padding(.horizontal, LVSpacing.base)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Agent: \(vm.model ?? "default brain"), \(statusText.lowercased())"
        )
        .task { await vm.load() }
    }

    private var statusText: String {
        switch vm.status {
        case .unknown: "Status unavailable"
        case .online: "Online"
        case .offline: "Offline"
        }
    }

    private var dotTone: Color? {
        switch vm.status {
        case .unknown: nil
        case .online: .green
        case .offline: palette.textSecondary.opacity(0.5)
        }
    }
}
