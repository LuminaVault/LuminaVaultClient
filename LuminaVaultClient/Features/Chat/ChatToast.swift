// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatToast.swift
//
// One transient notice for the whole chat surface.
//
// This replaces five independent `String?` slots — save-to-memory, job
// created, reminder set, voice error, attachment error — that each rendered as
// another conditional row stacked above the composer. Stacked rows meant the
// composer could be shoved down ~40pt while the user was mid-sentence, and two
// notices arriving together produced two bars rather than one message.
import SwiftUI

struct ChatToast: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Something the user asked for succeeded.
        case success
        /// Something failed, but the chat is still usable.
        case warning
    }

    let kind: Kind
    let text: String

    /// Derived rather than a fresh `UUID`, so re-deriving the same notice
    /// (`activeToast` recomputes on every read) keeps one stable identity and
    /// the transition doesn't restart.
    var id: String { "\(kind)-\(text)" }

    var icon: LVIcon {
        switch kind {
        case .success: .checkmarkCircleFill
        case .warning: .exclamationmarkTriangleFill
        }
    }

    var tint: Color {
        switch kind {
        case .success: .green
        case .warning: .orange
        }
    }
}

/// The toast surface itself. Overlays the top of the transcript rather than
/// occupying a row above the composer, so appearing never changes the layout
/// of anything the user is interacting with.
struct ChatToastView: View {
    @Environment(\.lvPalette) private var palette
    let toast: ChatToast

    var body: some View {
        HStack(spacing: LVSpacing.sm) {
            LVIconView(toast.icon, size: 15, tint: toast.tint)
            Text(toast.text)
                .lvFont(.footnote)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LVSpacing.base)
        .padding(.vertical, LVSpacing.sm)
        .lvGlassCard(cornerRadius: LVRadius.md, intensity: LVGlow.subtle)
        .padding(.horizontal, LVSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.text)
        .accessibilityAddTraits(.isStaticText)
    }
}
