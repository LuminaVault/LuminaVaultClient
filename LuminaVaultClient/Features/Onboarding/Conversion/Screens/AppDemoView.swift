// HER-287 — Screen 10: App demo (pick 3 sample captures).
//
// Tinder-style stack of curated sample captures filtered by the user's
// Screen 8 picks. Swipe right adds the capture to the demo vault, left
// skips. Auto-advance once 3 captures are accepted.

import SwiftUI

struct AppDemoView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(\.lvPalette) private var palette
    @State private var deck: [FunnelSampleCapture] = []
    @State private var topIndex: Int = 0
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        FunnelScreenChrome(
            headline: "Pick 3 things Lumina should learn first.",
            subhead: counterSubhead
        ) {
            ZStack {
                if state.demoPickedCaptureIDs.count >= 3 {
                    finishedView
                        .onAppear {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                state.advance()
                            }
                        }
                } else if topIndex < deck.count {
                    cardStack
                } else {
                    emptyDeck
                }
            }
            .frame(height: 420)
        }
        .onAppear {
            if deck.isEmpty {
                deck = FunnelSampleCapture.filtered(by: state.selectedCaptureSources)
            }
        }
    }

    private var counterSubhead: String {
        let remaining = max(0, 3 - state.demoPickedCaptureIDs.count)
        switch remaining {
        case 0: return "Done — Lumina has what it needs."
        case 1: return "Swipe right to remember. Pick 1 more."
        default: return "Swipe right to remember. Pick \(remaining) more."
        }
    }

    @ViewBuilder
    private var cardStack: some View {
        ZStack {
            ForEach(Array(deck.enumerated()), id: \.element.id) { index, capture in
                if index >= topIndex && index < topIndex + 2 {
                    card(for: capture, isTop: index == topIndex)
                        .offset(index == topIndex ? dragOffset : .zero)
                        .rotationEffect(.degrees(index == topIndex ? Double(dragOffset.width / 16) : 0))
                        .scaleEffect(index == topIndex ? 1.0 : 0.94)
                        .zIndex(Double(deck.count - index))
                        .gesture(index == topIndex ? swipeGesture(capture: capture) : nil)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: dragOffset)
                }
            }
        }
    }

    private func card(for capture: FunnelSampleCapture, isTop: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(capture.emoji).font(.system(size: 28))
                Text(capture.source.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.glowPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(palette.glowPrimary.opacity(0.12))
                    )
                Spacer()
            }
            Text(capture.title)
                .font(.system(size: 19, weight: .bold))
                .lineLimit(3)
            Text(capture.preview)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(5)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 380, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(palette.glowPrimary.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 14, y: 4)
    }

    private var emptyDeck: some View {
        VStack(spacing: 12) {
            Text("Nothing left to pick from.")
                .font(.system(size: 18, weight: .semibold))
            Button("Continue") { state.advance() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var finishedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(palette.glowPrimary)
            Text("Done. Lumina has what it needs.")
                .font(.system(size: 20, weight: .bold))
        }
    }

    private func swipeGesture(capture: FunnelSampleCapture) -> some Gesture {
        DragGesture()
            .onChanged { value in dragOffset = value.translation }
            .onEnded { value in
                let threshold: CGFloat = 110
                if value.translation.width > threshold {
                    accept(capture)
                } else if value.translation.width < -threshold {
                    skip()
                } else {
                    dragOffset = .zero
                }
            }
    }

    private func accept(_ capture: FunnelSampleCapture) {
        state.recordDemoPick(captureID: capture.id)
        withAnimation(.easeOut(duration: 0.25)) { dragOffset = CGSize(width: 500, height: 0) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            topIndex += 1
            dragOffset = .zero
        }
    }

    private func skip() {
        withAnimation(.easeOut(duration: 0.25)) { dragOffset = CGSize(width: -500, height: 0) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            topIndex += 1
            dragOffset = .zero
        }
    }
}
