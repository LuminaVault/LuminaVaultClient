// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/SystemStatusCardView.swift
//
// HER-244 — green/red dot for the configured Hermes instance. Tailscale
// reachability detail lands with HER-250 (server connection settings).

import SwiftUI

struct SystemStatusCardView: View {
    let isOnline: Bool

    var body: some View {
        DashboardCardShell(title: "System Status", icon: "antenna.radiowaves.left.and.right") {
            HStack(spacing: 10) {
                Circle()
                    .fill(isOnline ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOnline ? "Hermes reachable" : "Hermes unreachable")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.lvTextPrimary)
                    Text(isOnline ? "All systems operational." : "Check your network or server URL.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.lvTextSub)
                }
                Spacer()
            }
        }
    }
}
