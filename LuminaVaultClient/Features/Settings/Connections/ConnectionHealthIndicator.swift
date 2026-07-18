import SwiftUI

/// Shared connection vocabulary used by the hub and legacy connection panes.
/// A symbol accompanies every color so status remains clear when users enable
/// Differentiate Without Color.
struct ConnectionHealthDot: View {
    let health: ConnectionHealth

    var body: some View {
        LVStatusLumen(color: health.tint, symbolName: health.symbolName)
            .frame(width: 14, height: 14)
            .accessibilityLabel("Status: \(health.label)")
    }
}

struct ConnectionHealthBadge: View {
    let health: ConnectionHealth

    var body: some View {
        HStack(spacing: LVSpacing.xs) {
            ConnectionHealthDot(health: health)
                .accessibilityHidden(true)
            Text(health.label)
                .font(LVTypography.caption.font.weight(.medium))
        }
        .foregroundStyle(health.tint)
        .padding(.horizontal, LVSpacing.sm)
        .padding(.vertical, LVSpacing.xs)
        .background(health.tint.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(health.label)")
    }
}

extension ConnectionHealth {
    var label: String {
        switch self {
        case .connected: "Connected"
        case .needsSetup: "Needs setup"
        case .degraded: "Check"
        case .error: "Error"
        case .unknown: "Unknown"
        case .testing: "Testing"
        }
    }

    var tint: Color {
        switch self {
        case .connected: .green
        case .needsSetup: .secondary
        case .degraded: .orange
        case .error: .red
        case .unknown: .gray
        case .testing: .blue
        }
    }

    fileprivate var symbolName: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .needsSetup: "plus.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        case .testing: "arrow.triangle.2.circlepath"
        }
    }
}
