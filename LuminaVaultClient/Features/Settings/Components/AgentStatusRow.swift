// LuminaVaultClient/LuminaVaultClient/Features/Settings/Components/AgentStatusRow.swift
//
// Which brain is answering, and whether it is up.
//
// This replaces the Dashboard's "LUMINA COMMAND / AGENT CORE · ONLINE" panel.
// The information was worth keeping and the theatre was not, and Settings is
// where someone goes when they want to know what their agent is set to.

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class AgentStatusRowViewModel {
    private(set) var model: String?
    private(set) var provider: String?
    private(set) var online = false
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
            online = summary.agentOnline
            loaded = true
        } catch {
            // Staying unloaded is the honest state: the row shows the
            // default-brain copy and an offline dot rather than inventing a
            // model name.
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
                Circle()
                    .fill(vm.online ? Color.green : palette.textSecondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(vm.online ? "Online" : "Offline")
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.vertical, LVSpacing.md)
        .padding(.horizontal, LVSpacing.base)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Agent: \(vm.model ?? "default brain"), \(vm.online ? "online" : "offline")"
        )
        .task { await vm.load() }
    }
}
