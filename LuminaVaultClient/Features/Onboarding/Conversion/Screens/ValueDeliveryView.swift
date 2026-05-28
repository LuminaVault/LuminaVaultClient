// HER-287 — Screen 11: Value delivery + viral moment.
//
// Renders the 3 captures the user picked, plus a faux Lumina query
// + answer in their (yet-to-be-set) voice. Share button + start-trial
// CTA. Start-trial routes to the HER-211 universal paywall sheet via
// `appState.pendingPaywallID`.

import SwiftUI

struct ValueDeliveryView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(AppState.self) private var appState
    @Environment(\.lvPalette) private var palette
    @State private var shareItem: ShareItem?

    private var pickedCaptures: [FunnelSampleCapture] {
        FunnelSampleCapture.all.filter { state.demoPickedCaptureIDs.contains($0.id) }
    }

    var body: some View {
        FunnelScreenChrome(
            headline: "Here's what Lumina remembers about you so far.",
            primaryCTA: "Start my 14-day trial →",
            onPrimary: { state.advance() },
            secondaryCTA: "Send this to a friend",
            onSecondary: { presentShare() }
        ) {
            VStack(spacing: 16) {
                ForEach(pickedCaptures) { capture in
                    captureCard(capture)
                }
                luminaQueryCard
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.text])
        }
    }

    private func captureCard(_ capture: FunnelSampleCapture) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(capture.emoji)
                .font(.system(size: 24))
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(capture.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(capture.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private var luminaQueryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LVIconView(.sparkles, tint: palette.glowPrimary)
                Text("Try a question →")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\"What did I save today?\"")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            Divider().padding(.vertical, 4)
            Text("Lumina (in your voice):")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.glowPrimary)
            Text(answerText)
                .font(.system(size: 14))
                .lineSpacing(3)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(palette.glowPrimary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(palette.glowPrimary.opacity(0.35), lineWidth: 1)
        )
    }

    private var answerText: String {
        let count = pickedCaptures.count
        let firstTitle = pickedCaptures.first?.title ?? "a few captures"
        return "You saved \(count) thing\(count == 1 ? "" : "s") today — \(firstTitle) caught your eye. Common thread Lumina spotted: clarity about what actually matters to you right now."
    }

    private func presentShare() {
        state.telemetryClient.demoShare(captureCount: pickedCaptures.count)
        let lines = pickedCaptures.map { "• \($0.title)" }.joined(separator: "\n")
        shareItem = ShareItem(text: """
        I just set up my Lumina second brain. First captures:
        \(lines)

        Lumina is an AI that remembers everything you save — Safari articles, photos, voice memos, even Slack threads. In your voice.

        https://luminavault.com
        """)
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
