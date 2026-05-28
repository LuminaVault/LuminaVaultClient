// LuminaVaultClient/LuminaVaultClient/Features/Sync/SyncStatusBanner.swift
import SwiftUI

/// HER-39 — slim chip that pinpoints whether the sync queue is current,
/// has pending work, or has hit an error. Pinned at the top of
/// `MainTabView` so the user always knows whether the latest tap is
/// durable.
///
/// Visibility rules:
///   * `.idle` → hidden (no chip when nothing is pending).
///   * `.syncing` → blue / spinner with pending count.
///   * `.offline` → yellow "Saved locally — will sync when online".
///   * `.error` → red, taps to manually retry via Settings.
struct SyncStatusBanner: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let label = bannerLabel {
            HStack(spacing: 8) {
                // HER-291: kept as Image — runtime symbol name
                Image(systemName: label.icon)
                    .font(.caption)
                Text(label.text)
                    .font(.caption.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(label.background)
            .foregroundStyle(label.foreground)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private struct BannerLabel {
        let icon: String
        let text: String
        let background: Color
        let foreground: Color
    }

    private var bannerLabel: BannerLabel? {
        switch appState.syncState {
        case .idle:
            return nil
        case let .syncing(pending):
            return BannerLabel(
                icon: "arrow.triangle.2.circlepath",
                text: pending > 0 ? "Syncing \(pending) pending…" : "Syncing…",
                background: Color.blue.opacity(0.15),
                foreground: .blue
            )
        case .offline:
            return BannerLabel(
                icon: "wifi.slash",
                text: "Saved locally — will sync when online.",
                background: Color.yellow.opacity(0.18),
                foreground: .orange
            )
        case let .error(message):
            return BannerLabel(
                icon: "exclamationmark.triangle.fill",
                text: "Sync failed — \(message)",
                background: Color.red.opacity(0.18),
                foreground: .red
            )
        }
    }
}
