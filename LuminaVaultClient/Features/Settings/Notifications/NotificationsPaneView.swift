// LuminaVaultClient/LuminaVaultClient/Features/Settings/Notifications/NotificationsPaneView.swift
//
// HER-179 — Settings → Notifications: per-category opt-out toggles.

import LuminaVaultShared
import SwiftUI

struct NotificationsPaneView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: NotificationsPaneViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    switch vm.state {
                    case .loading:
                        ProgressView().tint(palette.primary).padding()
                    case .failed(let message):
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.lvTextMuted)
                            .padding(.horizontal)
                    case .loaded:
                        toggleCard(
                            title: "Daily digest",
                            subtitle: "Curated summary of what Lumina noticed.",
                            isOn: Binding(
                                get: { vm.digestEnabled },
                                set: { newValue in Task { await vm.toggle(.digest, value: newValue) } }
                            )
                        )
                        toggleCard(
                            title: "Nudges",
                            subtitle: "Lumina reaches out when patterns shift.",
                            isOn: Binding(
                                get: { vm.nudgeEnabled },
                                set: { newValue in Task { await vm.toggle(.nudge, value: newValue) } }
                            )
                        )
                        toggleCard(
                            title: "Chat replies",
                            subtitle: "Background chat responses.",
                            isOn: Binding(
                                get: { vm.chatEnabled },
                                set: { newValue in Task { await vm.toggle(.chat, value: newValue) } }
                            )
                        )
                        hermesRunsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Notifications")
        .lvBackground()
        .task { await vm.load() }
    }

    private var header: some View {
        Text("Choose how Lumina reaches you. Disabling a category suppresses the push but the underlying skill still runs.")
            .font(.system(size: 13))
            .foregroundStyle(palette.textSecondary)
    }

    /// Phase 1 — the two Hermes-run push categories. Both are delivered
    /// unconditionally today: the server honours per-tenant opt-out columns
    /// (M119) but `/v1/me/apns-categories` exposes no field for them, so
    /// these read as state rather than pretending to be switches. See
    /// `NotificationsPaneViewModel.editableCategories`.
    private var hermesRunsSection: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            Text("HERMES RUNS")
                .lvFont(.kicker)
                .kerning(0.8)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, LVSpacing.sm)

            statusCard(
                title: "Approval requests",
                subtitle: "Hermes asks before it runs a tool. Answer straight from the notification.",
                icon: "hand.raised.fill"
            )
            statusCard(
                title: "Run results",
                subtitle: "A run you started finished, failed or was stopped.",
                icon: "checkmark.seal"
            )

            Text("Always on. Turn them off for now in iOS Settings → Notifications → LuminaVault.")
                .lvFont(.caption)
                .foregroundStyle(Color.lvTextMuted)
        }
    }

    private func statusCard(title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: LVSpacing.md) {
            Image(systemName: icon)
                .lvFont(.bodyEmphasis)
                .foregroundStyle(palette.glowPrimary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                Text(title)
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: LVSpacing.sm)
            Text("On")
                .lvFont(.microTag)
                .foregroundStyle(palette.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.backgroundBase.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }

    private func toggleCard(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(palette.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.backgroundBase.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(palette.primary.opacity(0.15), lineWidth: 1)
        )
    }
}
