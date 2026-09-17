// LuminaVaultClient/LuminaVaultClient/Features/Home/GuidedStart/GuidedSpotlightOverlay.swift
//
// The spotlight: one dim with a hole in it, Hermie's line in a bubble beside
// the hole, and a Skip button.
//
// Applied **once**, on the `TabView`, through `.guidedSpotlight(…)`. The
// `spike/guided-anchors` probe measured that a single overlay there receives
// anchors from rows nested inside per-tab `NavigationStack`s accurately, so
// there is no reason for a second one — and four reasons in that spike to be
// careful about this exact view:
//
// * **Stale anchors.** A tab the user has left keeps publishing its last
//   geometry forever. The probe rendered two spotlights, the second over an
//   unrelated row. `anchors.anchor(for:on:)` filters by the owning tab, and
//   an anchor that lands outside the overlay is discarded here as well.
// * **Safe area.** The overlay's own space starts below it (origin ≈ y 90),
//   so without `ignoresSafeArea()` the dim stops short of the nav bar and
//   tab bar and the hole sits ~90pt off. Both are fixed by the same call.
// * **Unvisited tabs publish nothing.** That is normal, not an error: it is
//   the state of any tab that has not been built yet, and it resolves within
//   ~50ms of switching. The overlay degrades to a centred bubble with no
//   hole rather than guessing a rect.
// * **Sheets.** Anchors inside a presented sheet never reach an overlay
//   outside the sheet. None of the three steps needs that — step 2 points at
//   the Sync & Learn row on Home, not at anything inside a sheet — but a
//   future step that does will need its own overlay, not a change here.
//
// Not modal to assistive technology, deliberately: the whole point is that
// the control being taught stays reachable, so VoiceOver must be able to
// walk past the bubble and onto it. Focus moves to the bubble when a step
// opens, the line is the label, Skip is a real button, and the escape action
// skips.

import SwiftUI

struct GuidedSpotlightOverlay: View {
    /// `nil` renders nothing at all — no dim, no bubble. At most one step is
    /// ever active (contract), so one optional is the whole input.
    let step: GuidedStartStep?

    /// Which tab is on screen. Anchors from any other tab are ignored; `nil`
    /// means the visible tab hosts no guided targets, which degrades to the
    /// no-hole bubble.
    let activeTab: GuidedTab?

    let anchors: [GuidedAnchorID: Anchor<CGRect>]

    /// Driven even though the shipped `lumina_anims.riv` artboard is
    /// idle-only: the reactions below are host-UI scale, and an authored
    /// state machine picks the input up later with no code change.
    var hermieState: HermieMascotState = .thinking

    let onSkip: () -> Void

    @State private var bubbleSize: CGSize = .zero
    @State private var appeared = false
    @AccessibilityFocusState private var bubbleFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the hole is grown past the control it frames.
    private static let holeInset: CGFloat = 8
    private static let dimOpacity: Double = 0.55
    private static let holeRadius: CGFloat = LVRadius.md
    /// Gap between the hole and the bubble, and the bubble's minimum margin
    /// from the screen edge.
    private static let gap: CGFloat = LVSpacing.md
    private static let edgeMargin: CGFloat = LVSpacing.xl
    private static let bubbleMaxWidth: CGFloat = 340
    private static let mascotSize: CGFloat = 56
    private static let tailSize = CGSize(width: 18, height: 9)

    @ViewBuilder
    var body: some View {
        if let step {
            GeometryReader { proxy in
                let hole = resolvedHole(step: step, proxy: proxy)
                ZStack(alignment: .topLeading) {
                    scrim(container: proxy.size, hole: hole)
                    touchBlockers(container: proxy.size, hole: hole)
                    bubble(step: step, container: proxy.size, hole: hole)
                }
            }
            // Both halves of the spike's safe-area finding: the dim reaches
            // the nav bar and the tab bar, and the resolved anchors are in
            // the same full-screen space the dim is drawn in.
            .ignoresSafeArea()
            // The overlay view itself outlives any one step — only its
            // content comes and goes — so this has to reset when the step
            // closes. Left latched, the bubble's entrance played once ever
            // and steps two and three snapped in at full size.
            .onAppear { appeared = true }
            .onDisappear { appeared = false }
        }
    }

    // MARK: - Geometry

    /// The hole, in the overlay's own coordinate space, or `nil` for the
    /// degraded no-hole presentation.
    ///
    /// Discarding a rect that does not intersect the overlay covers the
    /// target having scrolled off screen: a stale-but-correctly-tagged anchor
    /// is still the wrong thing to cut a hole over.
    private func resolvedHole(step: GuidedStartStep, proxy: GeometryProxy) -> CGRect? {
        guard let anchor = anchors.anchor(for: step.target, on: activeTab) else { return nil }
        let rect = proxy[anchor].insetBy(dx: -Self.holeInset, dy: -Self.holeInset)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let container = CGRect(origin: .zero, size: proxy.size)
        guard rect.intersects(container) else { return nil }
        return rect
    }

    // MARK: - Dim

    /// One even-odd filled path rather than a blend-mode mask: same picture,
    /// no compositing group, and it renders identically in a snapshot.
    private func scrim(container: CGSize, hole: CGRect?) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: container))
            if let hole {
                path.addRoundedRect(
                    in: hole,
                    cornerSize: CGSize(width: Self.holeRadius, height: Self.holeRadius),
                    style: .continuous
                )
            }
        }
        .fill(Color.black.opacity(Self.dimOpacity), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Everything except the hole swallows touches, so the hole is the only
    /// way through and the taught control stays usable. Drawn clear — the dim
    /// above is the visible part.
    private func touchBlockers(container: CGSize, hole: CGRect?) -> some View {
        ForEach(Array(blockerRects(container: container, hole: hole).enumerated()), id: \.offset) { _, rect in
            Color.clear
                .frame(width: rect.width, height: rect.height)
                .contentShape(.rect)
                .onTapGesture {}
                // A tap gesture alone leaves a drag to reach the list
                // underneath and scroll the spotlit row out from under the
                // hole; this claims the touch for the overlay.
                .gesture(DragGesture(minimumDistance: 0))
                .position(x: rect.midX, y: rect.midY)
                .accessibilityHidden(true)
        }
    }

    private func blockerRects(container: CGSize, hole: CGRect?) -> [CGRect] {
        let full = CGRect(origin: .zero, size: container)
        guard let hole = hole?.intersection(full), !hole.isNull, !hole.isEmpty else { return [full] }
        return [
            CGRect(x: 0, y: 0, width: container.width, height: hole.minY),
            CGRect(x: 0, y: hole.maxY, width: container.width, height: container.height - hole.maxY),
            CGRect(x: 0, y: hole.minY, width: hole.minX, height: hole.height),
            CGRect(x: hole.maxX, y: hole.minY, width: container.width - hole.maxX, height: hole.height),
        ].filter { $0.width > 0.5 && $0.height > 0.5 }
    }

    // MARK: - Bubble

    private func bubble(step: GuidedStartStep, container: CGSize, hole: CGRect?) -> some View {
        let placement = bubblePlacement(container: container, hole: hole)

        return VStack(alignment: .leading, spacing: LVSpacing.md) {
            HStack(alignment: .top, spacing: LVSpacing.md) {
                HermieMascotView(state: hermieState, size: Self.mascotSize)
                    .scaleEffect(mascotScale)
                    .lvAnimation(LVMotion.standardSpring, value: hermieState)
                    .accessibilityHidden(true)

                Text(step.hermieLine)
                    .lvFont(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Focus lands here when the step opens, and the text is
                    // its own label. Nothing traps it: the overlay never
                    // claims `.isModal`, so the next swipe reaches the real
                    // control being taught.
                    .accessibilityFocused($bubbleFocused)
            }

            HStack {
                Spacer(minLength: 0)
                Button(GuidedStartCopy.skip, action: onSkip)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Closes this step and leaves the checklist open")
            }
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: Self.bubbleMaxWidth)
        .background(bubbleBackground(container: container, hole: hole, placement: placement))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { bubbleSize = $0 }
        .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .lvAnimation(LVMotion.standardSpring, value: appeared)
        .lvAnimation(LVMotion.standard, value: placement.centerY)
        .position(x: container.width / 2, y: placement.centerY)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onSkip)
        .onAppear { bubbleFocused = true }
        .onChange(of: step) { _, _ in bubbleFocused = true }
    }

    private struct BubblePlacement {
        let centerY: CGFloat
        /// `true` when the bubble sits under the hole, which is also which
        /// way the tail points.
        let isBelow: Bool
    }

    /// Below the hole when the room under it fits the bubble, otherwise
    /// above; the result is then clamped inside the screen, so a hole near an
    /// edge cannot push the bubble off it.
    ///
    /// The height is measured (`onGeometryChange`) rather than assumed,
    /// because the line is one to two lines at default Dynamic Type and
    /// considerably more at accessibility sizes.
    private func bubblePlacement(container: CGSize, hole: CGRect?) -> BubblePlacement {
        let height = bubbleSize.height > 0 ? bubbleSize.height : 160
        guard let hole else {
            return BubblePlacement(centerY: container.height / 2, isBelow: true)
        }
        let roomBelow = container.height - hole.maxY - Self.gap - Self.edgeMargin
        let roomAbove = hole.minY - Self.gap - Self.edgeMargin
        // Prefer below — reading downward from the thing being pointed at —
        // and only go above when below genuinely does not fit and above does.
        let isBelow = roomBelow >= height || roomAbove < height
        let unclamped = isBelow
            ? hole.maxY + Self.gap + height / 2
            : hole.minY - Self.gap - height / 2
        let lower = Self.edgeMargin + height / 2
        let upper = container.height - Self.edgeMargin - height / 2
        let centerY = upper >= lower ? min(max(unclamped, lower), upper) : container.height / 2
        return BubblePlacement(centerY: centerY, isBelow: isBelow)
    }

    private func bubbleBackground(
        container: CGSize,
        hole: CGRect?,
        placement: BubblePlacement
    ) -> some View {
        RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay(alignment: placement.isBelow ? .top : .bottom) {
                if let hole {
                    GuidedBubbleTail()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(width: Self.tailSize.width, height: Self.tailSize.height)
                        .rotationEffect(.degrees(placement.isBelow ? 0 : 180))
                        .offset(
                            x: tailOffset(container: container, hole: hole),
                            y: placement.isBelow ? -Self.tailSize.height + 1 : Self.tailSize.height - 1
                        )
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
    }

    /// Points the tail at the hole, kept far enough from the bubble's corners
    /// that it never grows out of the rounded part.
    private func tailOffset(container: CGSize, hole: CGRect) -> CGFloat {
        let bubbleWidth = bubbleSize.width > 0
            ? bubbleSize.width
            : min(Self.bubbleMaxWidth, container.width)
        let limit = max(0, bubbleWidth / 2 - LVRadius.card - Self.tailSize.width)
        return min(max(hole.midX - container.width / 2, -limit), limit)
    }

    private var mascotScale: CGFloat {
        guard !reduceMotion else { return 1 }
        switch hermieState {
        case .happy, .celebrating: return 1.08
        default: return 1
        }
    }
}

// MARK: - Tail

/// An upward-pointing triangle; rotated 180° when the bubble is above the
/// hole.
private struct GuidedBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// MARK: - Attaching it

extension View {
    /// Attach **once**, to the `TabView`. Anywhere lower and the anchors from
    /// the other tabs never arrive; anywhere the safe area is already
    /// consumed and the dim comes up short.
    ///
    /// `activeTab` is passed rather than read from `\.lvActiveTab` because
    /// that environment value is injected *inside* the TabView, and an
    /// overlay attached outside it would not see it.
    func guidedSpotlight(
        step: GuidedStartStep?,
        activeTab: GuidedTab?,
        hermieState: HermieMascotState = .thinking,
        onSkip: @escaping () -> Void
    ) -> some View {
        overlayPreferenceValue(GuidedAnchorKey.self) { anchors in
            GuidedSpotlightOverlay(
                step: step,
                activeTab: activeTab,
                anchors: anchors,
                hermieState: hermieState,
                onSkip: onSkip
            )
        }
    }
}
