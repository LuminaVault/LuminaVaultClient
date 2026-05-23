// HER-287 — Screen 12: Notification permission priming (post-demo).
//
// Frames permission around USER benefit (nudges they'll value). Tap
// "Enable nudges" calls UNUserNotificationCenter.requestAuthorization.
// Tap "Not now" advances without prompting. Either path resolves the
// funnel and fires onResolved (caller triggers paywall + dismisses
// the funnel).

import SwiftUI
import UserNotifications

struct NotificationPrimeView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(\.lvPalette) private var palette
    let onResolved: () -> Void

    @State private var isRequesting = false

    private struct Bullet: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let body: String
    }

    private let bullets: [Bullet] = [
        .init(id: 0, icon: "📈", title: "Daily insights",
              body: "Patterns from your week, ready before coffee."),
        .init(id: 1, icon: "🎯", title: "Goal nudges",
              body: "Lumina checks in based on what you told it matters."),
        .init(id: 2, icon: "🔔", title: "Capture summaries",
              body: "Quick recap of what you saved each day."),
    ]

    var body: some View {
        FunnelScreenChrome(
            headline: "Lumina nudges you when it matters.",
            subhead: "Three kinds. You'll never get spam.",
            primaryCTA: isRequesting ? "Asking…" : "Enable nudges",
            primaryEnabled: !isRequesting,
            onPrimary: { Task { await enableNudges() } },
            secondaryCTA: "Not now",
            onSecondary: { resolveSkipped() }
        ) {
            VStack(spacing: 12) {
                ForEach(bullets) { bullet in
                    HStack(alignment: .top, spacing: 14) {
                        Text(bullet.icon).font(.system(size: 26))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bullet.title)
                                .font(.system(size: 15, weight: .semibold))
                            Text(bullet.body)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(palette.glowPrimary.opacity(0.25), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func enableNudges() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        let center = UNUserNotificationCenter.current()
        var granted = false
        do {
            granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            // Permission denial / errors are silent — never punish the
            // user for this choice. Funnel resolves either way. HER-295
            // still fires the telemetry with `granted: false` so the
            // funnel chart distinguishes "asked-and-denied" from
            // "skipped without asking".
            granted = false
        }
        state.telemetryClient.notificationPrompted(granted: granted)
        // Hop to main actor; granted-token registration is owned by
        // NotificationsAppDelegate (HER-214). Funnel just resolves.
        onResolved()
    }

    private func resolveSkipped() {
        onResolved()
    }
}
