// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/DashboardActionRowView.swift
//
// HER-244 — three big buttons at the bottom of the Dashboard:
//   New Session · Trigger Compile · Ask Anything
// New Session + Ask Anything are stubs that defer to the Think tab
// (HER-107 / HER-245) until those surfaces ship dedicated entry points.

import SwiftUI

struct DashboardActionRowView: View {

    @Environment(\.lvPalette) private var palette

    let isCompiling: Bool
    let onNewSession: () -> Void
    let onTriggerCompile: () -> Void
    let onAskAnything: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            actionButton(
                title: "New Session",
                icon: "plus.bubble",
                isPrimary: false,
                isLoading: false,
                action: onNewSession
            )
            actionButton(
                title: "Trigger Compile",
                icon: "wand.and.stars",
                isPrimary: true,
                isLoading: isCompiling,
                action: onTriggerCompile
            )
            actionButton(
                title: "Ask Anything",
                icon: "questionmark.bubble",
                isPrimary: false,
                isLoading: false,
                action: onAskAnything
            )
        }
    }

    private func actionButton(
        title: String,
        icon: String,
        isPrimary: Bool,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(palette.backgroundBase)
                        .frame(height: 22)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(height: 22)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isPrimary ? palette.backgroundBase : palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isPrimary ? palette.primary : palette.backgroundBase.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isPrimary ? Color.clear : palette.primary.opacity(0.25),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .lvGlowPress()
        .disabled(isLoading)
    }
}
