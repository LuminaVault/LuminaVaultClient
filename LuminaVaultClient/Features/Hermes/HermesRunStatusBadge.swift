// LuminaVaultClient/LuminaVaultClient/Features/Hermes/HermesRunStatusBadge.swift
//
// Hermes Companion Phase 1 — the one place run status turns into words and
// colour, so a run reads the same on the list, on its detail screen and in
// the chat composer's confirmation.

import LuminaVaultShared
import SwiftUI

extension HermesRunStatus {
    var lvLabel: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Running"
        case .waitingForApproval: return "Needs you"
        case .completed: return "Done"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        case .lost: return "Lost"
        }
    }

    var lvSystemImage: String {
        switch self {
        case .queued: return "clock"
        case .running: return "bolt.fill"
        case .waitingForApproval: return "hand.raised.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .stopped: return "stop.circle"
        case .lost: return "questionmark.circle"
        }
    }

    func lvTint(_ palette: LVPalette) -> Color {
        switch self {
        case .queued: return palette.textSecondary
        case .running: return palette.accent
        case .waitingForApproval: return palette.glowPrimary
        case .completed: return palette.primary
        case .failed: return .red
        case .stopped, .lost: return palette.textSecondary
        }
    }

    /// Why a `lost` run is worth explaining: it is not a Hermes failure, it
    /// is LuminaVault losing track after a restart, and the transcript up to
    /// that point is still real.
    var lvExplanation: String? {
        switch self {
        case .lost:
            return "LuminaVault lost track of this run after a restart. Everything above it still happened."
        case .waitingForApproval:
            return "Hermes is holding a tool call until you answer."
        default:
            return nil
        }
    }
}

struct HermesRunStatusBadge: View {
    @Environment(\.lvPalette) private var palette
    let status: HermesRunStatus

    var body: some View {
        HStack(spacing: LVSpacing.xs) {
            Image(systemName: status.lvSystemImage)
            Text(status.lvLabel)
        }
        .lvFont(.microTag)
        .foregroundStyle(status.lvTint(palette))
        .padding(.horizontal, LVSpacing.sm)
        .padding(.vertical, LVSpacing.xs)
        .background(
            Capsule().fill(status.lvTint(palette).opacity(0.14))
        )
        .accessibilityLabel("Status: \(status.lvLabel)")
    }
}
