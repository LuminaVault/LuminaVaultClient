// LuminaVaultClient/LuminaVaultClient/Features/Settings/Appearance/ConnectionBadge.swift
// HER-255: small green/red status pill. Used first on the Hermes Gateway row
// per the issue spec; reusable on any "is this thing connected?" surface.
import SwiftUI

enum ConnectionState: Equatable {
    case connected
    case disconnected
    case unknown

    var label: String {
        switch self {
        case .connected:    return "Connected"
        case .disconnected: return "Disconnected"
        case .unknown:      return "Unknown"
        }
    }

    var tint: Color {
        switch self {
        case .connected:    return .green
        case .disconnected: return .red
        case .unknown:      return .gray
        }
    }
}

struct ConnectionBadge: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: LVSpacing.sm) {
            Circle()
                .fill(state.tint)
                .frame(width: 8, height: 8)
                .shadow(color: state.tint.opacity(0.6), radius: 4)
            Text(state.label)
                .font(LVTypography.caption.font.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, LVSpacing.sm)
        .padding(.vertical, LVSpacing.xs)
        .background {
            Capsule()
                .fill(state.tint.opacity(0.12))
                .overlay {
                    Capsule().stroke(state.tint.opacity(0.4), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(state.label)")
    }
}
