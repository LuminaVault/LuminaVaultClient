// HER-287 — Screen 5: Swipe cards (pain amplification, tinder-style).
//
// Cards are stacked. Drag right to agree, left to dismiss. Auto-advance
// to the next funnel step after the last card resolves.

import SwiftUI

struct SwipeCardsView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(\.lvPalette) private var palette
    @State private var topIndex: Int = 0
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        FunnelScreenChrome(
            headline: "Swipe right on what feels true.",
            subhead: "Left to dismiss."
        ) {
            ZStack {
                if topIndex >= FunnelSwipeCard.all.count {
                    completion
                        .onAppear {
                            // Defer advance to next runloop so the
                            // animation has a frame to settle.
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                state.advance()
                            }
                        }
                } else {
                    cardStack
                }
            }
            .frame(height: 380)
        }
    }

    @ViewBuilder
    private var cardStack: some View {
        ZStack {
            ForEach(Array(FunnelSwipeCard.all.enumerated()), id: \.element.id) { index, card in
                if index >= topIndex && index < topIndex + 2 {
                    cardView(for: card, isTop: index == topIndex)
                        .offset(index == topIndex ? dragOffset : CGSize(width: 0, height: 14))
                        .rotationEffect(.degrees(index == topIndex ? Double(dragOffset.width / 16) : 0))
                        .scaleEffect(index == topIndex ? 1.0 : 0.94)
                        .opacity(index == topIndex ? 1 : 0.6)
                        .zIndex(Double(FunnelSwipeCard.all.count - index))
                        .gesture(index == topIndex ? swipeGesture(cardID: card.id) : nil)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: dragOffset)
                }
            }
        }
    }

    private func cardView(for card: FunnelSwipeCard, isTop: Bool) -> some View {
        VStack(spacing: 16) {
            LVIconView(.quoteOpening, size: 28, tint: palette.glowPrimary.opacity(0.7))
            Text(card.statement)
                .font(.system(size: 19, weight: .medium))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 8)
            Spacer()
            if isTop {
                HStack(spacing: 36) {
                    swipeButton(icon: .xmark, label: "Skip", tint: .red) {
                        finish(cardID: card.id, agreed: false)
                    }
                    swipeButton(icon: .checkmark, label: "True", tint: .green) {
                        finish(cardID: card.id, agreed: true)
                    }
                }
            }
        }
        // Back cards render as a blank card edge — hide text so it can't
        // bleed through the near-transparent front-card surface.
        .opacity(isTop ? 1 : 0)
        // …and keep them out of the VoiceOver rotor, which ignores opacity.
        .accessibilityHidden(!isTop)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 360)
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

    /// The two hints used to be inert decoration, which left the swipe the
    /// only way to answer — unusable under VoiceOver, and awkward for anyone
    /// who reads the hint as a button. They are real controls now; the drag
    /// still works and both paths land in `finish(cardID:agreed:)`.
    private func swipeButton(
        icon: LVIcon,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: LVSpacing.xs) {
                LVIconView(icon, size: 16, tint: tint, weight: .bold)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: LVSize.tapTarget, minHeight: LVSize.tapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var completion: some View {
        VStack(spacing: 12) {
            LVIconView(.sparkles, size: 36, tint: palette.glowPrimary)
            Text("Got it.")
                .font(.system(size: 22, weight: .bold))
            Text("Pulling those into your Lumina view…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private func swipeGesture(cardID: Int) -> some Gesture {
        DragGesture()
            .onChanged { value in dragOffset = value.translation }
            .onEnded { value in
                let threshold: CGFloat = 110
                if value.translation.width > threshold {
                    finish(cardID: cardID, agreed: true)
                } else if value.translation.width < -threshold {
                    finish(cardID: cardID, agreed: false)
                } else {
                    dragOffset = .zero
                }
            }
    }

    private func finish(cardID: Int, agreed: Bool) {
        state.recordSwipe(cardID: cardID, agreed: agreed)
        // Fling animation
        withAnimation(.easeOut(duration: 0.25)) {
            dragOffset = CGSize(width: agreed ? 500 : -500, height: 0)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            topIndex += 1
            dragOffset = .zero
        }
    }
}
