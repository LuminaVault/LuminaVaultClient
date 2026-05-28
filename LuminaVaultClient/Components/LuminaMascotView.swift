// LuminaVaultClient/LuminaVaultClient/Components/LuminaMascotView.swift
//
// HER-152 — Rive mascot animation states (Lumina).
//
// The mascot rig itself lives in `HermieMascotView` (HER-40 / HER-179).
// HER-152 is the branding pass that exposes the mascot under the "Lumina"
// name plus the full state set the product pitch calls for: idle,
// thinking, happy, sad, sleeping, learning, celebrating.
//
// Rather than fork the Rive plumbing, `LuminaMascotView` is a thin facade
// over `HermieMascotView` so callers get the issue's named API
// (`LuminaMascotView().state(.thinking)`) without a second `RiveViewModel`
// load path to keep in sync.

import SwiftUI

/// Animation states for the Lumina mascot. Alias of the underlying rig
/// state so call sites can read in "Lumina" terms.
///
/// HER-152 — states flow from chat (`.thinking`/`.happy`), kb-compile and
/// capture progress (`.learning`), failures (`.sad`), idle timeout
/// (`.sleeping`) and streak milestones (`.celebrating`).
public typealias LuminaMascotState = HermieMascotState

public struct LuminaMascotView: View {

    private let state: LuminaMascotState
    private let size: CGFloat
    private let fallbackImageName: String

    public init(
        state: LuminaMascotState = .idle,
        size: CGFloat = 220,
        fallbackImageName: String = "Mascot"
    ) {
        self.state = state
        self.size = size
        self.fallbackImageName = fallbackImageName
    }

    public var body: some View {
        HermieMascotView(
            state: state,
            size: size,
            fallbackImageName: fallbackImageName
        )
        .accessibilityLabel("Lumina mascot — \(state.rawValue)")
    }

    /// Drives the mascot to a new state. Mirrors the issue's intended
    /// ergonomics: `LuminaMascotView().state(.thinking)`.
    public func state(_ newState: LuminaMascotState) -> LuminaMascotView {
        LuminaMascotView(
            state: newState,
            size: size,
            fallbackImageName: fallbackImageName
        )
    }
}

#Preview("All states · Dark") {
    ScrollView {
        VStack(spacing: LVSpacing.xl) {
            ForEach(LuminaMascotState.allCases, id: \.self) { state in
                VStack(spacing: LVSpacing.sm) {
                    LuminaMascotView(state: state, size: 120)
                    Text(state.rawValue)
                        .font(LVTypography.caption.font)
                }
            }
        }
        .padding(.vertical, LVSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
    .lvBackground()
    .preferredColorScheme(.dark)
}
