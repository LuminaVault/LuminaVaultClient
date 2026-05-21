// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/DashboardCardShell.swift
//
// HER-244 — reusable card chrome for the OS Shell Home/Dashboard. Mirrors
// the established SpaceCardView pattern (.lvNavy fill + .lvCyan stroke +
// 16-pt corner radius) so cards land in the same visual family as the
// rest of the app.

import SwiftUI

struct DashboardCardShell<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.lvCyan)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.lvTextSub)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.lvNavy.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.lvCyan.opacity(0.15), lineWidth: 1)
        )
    }
}
