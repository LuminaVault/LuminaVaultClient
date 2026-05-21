// LuminaVaultClient/LuminaVaultClient/Features/Settings/Notifications/NotificationsPaneView.swift
//
// HER-179 — Settings → Notifications: per-category opt-out toggles.

import LuminaVaultShared
import SwiftUI

struct NotificationsPaneView: View {
    @State var vm: NotificationsPaneViewModel

    var body: some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    switch vm.state {
                    case .loading:
                        ProgressView().tint(.lvCyan).padding()
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
            .foregroundStyle(Color.lvTextSub)
    }

    private func toggleCard(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.lvTextPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.lvTextSub)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.lvCyan)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.lvNavy.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.lvCyan.opacity(0.15), lineWidth: 1)
        )
    }
}
