// LuminaVaultClient/LuminaVaultClient/Features/Home/GuidedStart/GuidedStartCard.swift
//
// "Get started with Hermie" — the persistent card at the top of Home.
//
// A checklist, not a tour. The contract's reasoning (`docs/guided-start.md`)
// is that auto-triggered tours complete at roughly a quarter of the rate of
// the same steps launched from a card, so the card sits there and waits.
//
// Pure presentation on purpose: it takes a `GuidedStartProgress`, a mascot
// state, an optional inline message and two closures, and owns no reference
// to the coordinator, no fetching and no phase machine. That is what lets a
// snapshot suite render all four progress states without standing up a
// network stack, and it keeps the visibility rule (`loaded && !allDone &&
// !dismissed`) where it belongs — at the call site, in the next slice.
//
// Styling is stock iOS: an inset-grouped card on
// `secondarySystemGroupedBackground`, hairline separators between rows, SF
// Symbols, system label colours. Home was rebuilt to the native shell in
// ADR 0001, so there is no glass and no glow here beyond `lvPulse` on the
// one row the user should tap next.

import SwiftUI

struct GuidedStartCard: View {
    /// What is done and what is next. `GuidedStartProgress(nil)` — no
    /// snapshot in hand — renders as 0 of 3; whether to show the card at all
    /// on a missing snapshot is the visibility rule's call, not this view's.
    let progress: GuidedStartProgress

    /// The contract's reaction vocabulary: `idle` at rest, `thinking` while a
    /// step is open, `happy` on a completion, `celebrating` at the end. The
    /// shipped artboard is idle-only, so today this only changes the host-UI
    /// bounce below — but it is still driven, so an authored state machine
    /// lights up with no code change here.
    var hermieState: HermieMascotState = .idle

    /// The coordinator's `inlineMessage`: the "Save something first" guard,
    /// or a dismiss that failed to persist.
    var message: String?

    let onSelect: (GuidedStartStep) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Snapshot suites set this false to freeze the pulse. `lvPulse` starts a
    /// `repeatForever` from `onAppear`, which `transaction.disablesAnimations`
    /// does not reach, so without this seam two captures of the same state
    /// catch the row at different scales.
    @Environment(\.lvAmbientMotionEnabled) private var ambientMotionEnabled

    private static let mascotSize: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            header
            rows
            if progress.isAllDone {
                completionLine
            }
            if let message {
                inlineMessage(message)
            }
        }
        .padding(LVSpacing.base)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .contain)
        // The group stop announces how far along you are, not just the
        // headline — "two of three" is the part worth hearing when you land
        // on the card and the rows are still ahead of you.
        .accessibilityLabel(
            "\(GuidedStartCopy.headline), \(GuidedStartCopy.progress(completed: progress.completedCount))"
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: LVSpacing.md) {
            // Below `HermieMascotView`'s 64pt Rive threshold, so this is the
            // static mascot image — one deterministic frame, which is what a
            // snapshot needs and what a 56pt avatar can legibly show anyway.
            HermieMascotView(state: hermieState, size: Self.mascotSize)
                .scaleEffect(mascotScale)
                .lvAnimation(LVMotion.standardSpring, value: hermieState)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LVSpacing.hairline) {
                Text(GuidedStartCopy.headline)
                    .lvFont(.headline)
                    .foregroundStyle(.primary)

                Text(GuidedStartCopy.progress(completed: progress.completedCount))
                    .lvFont(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: LVSpacing.sm)

            Button(action: onDismiss) {
                LVIconView(.xmark, size: 14, tint: Color.secondary, weight: .semibold)
                    .frame(width: LVSize.tapTarget, height: LVSize.tapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide Get started with Hermie")
        }
    }

    /// A small settle on the mascot when the reaction changes. `lvAnimation`
    /// collapses it to a cross-fade under Reduce Motion; the scale itself is
    /// dropped too, so nothing moves at all.
    private var mascotScale: CGFloat {
        guard !reduceMotion else { return 1 }
        switch hermieState {
        case .happy, .celebrating: return 1.08
        default: return 1
        }
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(GuidedStartStep.allCases.enumerated()), id: \.element) { index, step in
                if index > 0 {
                    Divider().padding(.leading, LVSpacing.xl + LVSpacing.md)
                }
                row(step, index: index)
            }
        }
    }

    private func row(_ step: GuidedStartStep, index: Int) -> some View {
        let isDone = progress.completed.contains(step)
        let isNext = progress.next == step

        return Button {
            onSelect(step)
        } label: {
            HStack(spacing: LVSpacing.md) {
                indicator(isDone: isDone, index: index)
                    .frame(width: LVSpacing.xl, height: LVSpacing.xl)

                Text(step.title)
                    .lvFont(.body)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .strikethrough(isDone, color: .secondary)

                Spacer(minLength: LVSpacing.sm)

                LVIconView(.chevronRight, size: 13, tint: Color.secondary.opacity(0.6), weight: .semibold)
            }
            .padding(.vertical, LVSpacing.md)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Only the next incomplete row pulses, so the card always has exactly
        // one thing to look at. Frozen for snapshots and under Reduce Motion
        // (`lvPulse` gates on that itself).
        .lvPulse(active: isNext && ambientMotionEnabled)
        .accessibilityLabel("Step \(index + 1) of \(GuidedStartStep.allCases.count), \(step.title)")
        .accessibilityValue(isDone ? "Done" : "Not started")
        .accessibilityHint(isDone ? "" : step.hermieLine)
    }

    @ViewBuilder
    private func indicator(isDone: Bool, index: Int) -> some View {
        if isDone {
            LVIconView(.checkmarkCircleFill, size: 22, tint: Color.accentColor)
        } else {
            ZStack {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.5)
                Text("\(index + 1)")
                    .lvFont(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footers

    private var completionLine: some View {
        Text(GuidedStartCopy.completion)
            .lvFont(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func inlineMessage(_ text: String) -> some View {
        Text(text)
            .lvFont(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Previews

#Preview("Nothing done") {
    GuidedStartCard(progress: GuidedStartProgress(nil), onSelect: { _ in }, onDismiss: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}
