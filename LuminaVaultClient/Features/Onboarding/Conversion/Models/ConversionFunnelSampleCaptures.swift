// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Conversion/Models/ConversionFunnelSampleCaptures.swift
//
// HER-287 — curated sample captures used by Screen 10 (App Demo).
// Picks are filtered by the user's Screen 8 capture-source selections
// so the demo card stack only surfaces sources the user said they care
// about. Sample data only — these never persist beyond the funnel.

import Foundation

struct FunnelSampleCapture: Identifiable, Sendable, Equatable {
    let id: UUID
    let title: String
    let preview: String
    let source: FunnelCaptureSource
    let emoji: String

    static let all: [FunnelSampleCapture] = [
        .init(
            id: UUID(),
            title: "Steve Jobs Stanford commencement",
            preview: "\"Your time is limited, so don't waste it living someone else's life.\"",
            source: .safariArticles,
            emoji: "📄"
        ),
        .init(
            id: UUID(),
            title: "Whiteboard sketch — focus loop",
            preview: "Three-arrow diagram: capture → review → act. Notes about Sunday review cadence.",
            source: .photos,
            emoji: "📸"
        ),
        .init(
            id: UUID(),
            title: "Sunday review voice memo",
            preview: "2 minutes — \"This week I learned that I'm sharper before noon. Need to protect mornings.\"",
            source: .voiceMemos,
            emoji: "🎤"
        ),
        .init(
            id: UUID(),
            title: "Tuesday workout — 38 min cycling",
            preview: "Zone 2, avg HR 142. Felt strong; sleep was 7h 12m the night before.",
            source: .healthData,
            emoji: "❤️"
        ),
        .init(
            id: UUID(),
            title: "Stratechery — AI memory and the personal corpus",
            preview: "Why AI without persistent memory is a stateless feature, not a product. The personal corpus is the moat.",
            source: .safariArticles,
            emoji: "📰"
        ),
        .init(
            id: UUID(),
            title: "Slack — pricing decision thread",
            preview: "Decision: $14.99/mo Pro with 7-day trial. Reasoning: matches Notion AI; lower friction than annual.",
            source: .hermesGateways,
            emoji: "💬"
        ),
        .init(
            id: UUID(),
            title: "Quick note — what I learned this week",
            preview: "Three patterns: morning focus, evening review, mid-day walk = my best output days.",
            source: .manualNotes,
            emoji: "📝"
        ),
    ]

    /// Filter for the demo card stack: only return captures whose
    /// source the user selected on Screen 8. If the user picked nothing
    /// (skipped or zero selections), return everything so the demo
    /// still has cards.
    static func filtered(by sources: Set<FunnelCaptureSource>) -> [FunnelSampleCapture] {
        if sources.isEmpty { return all }
        return all.filter { sources.contains($0.source) }
    }
}

// MARK: - Testimonials (Screen 4 — Social Proof)

struct FunnelTestimonial: Identifiable, Sendable, Equatable {
    let id: Int
    let initials: String
    let persona: String
    let quote: String

    /// Ship-guard source of truth (HER-296).
    ///
    /// The entries below are placeholders. Apple §3.1.2 paywall App Review
    /// requires real review screenshots — placeholders read as "lorem ipsum"
    /// and risk rejection. Screen 4 feeds the paywall screenshot.
    ///
    /// Flip to `false` IN THE SAME COMMIT that swaps real testimonials in.
    /// While `true`, `verified` logs a DEBUG warning on every Screen 4
    /// render so placeholders can't quietly reach a build.
    static let containsUnverifiedPlaceholders = true

    /// Read path for Screen 4. Always read this, never `entries` directly,
    /// so the placeholder ship-guard runs. Warning is DEBUG-only and
    /// non-fatal — neither debug nor release builds crash on it.
    static var verified: [FunnelTestimonial] {
        #if DEBUG
        if containsUnverifiedPlaceholders {
            print(
                "⚠️ HER-296: Screen 4 still shows placeholder testimonials. Swap in real "
                    + "TestFlight reviews (written consent on file), then set "
                    + "containsUnverifiedPlaceholders = false before the paywall ships."
            )
        }
        #endif
        return entries
    }

    // TODO(HER-296): replace all 3 placeholders with real testimonials
    // (50–80 words each) from consented TestFlight testers, then flip
    // `containsUnverifiedPlaceholders` to false.
    //
    // Per entry, add an audit comment on the line above it — DO NOT commit
    // consent forms to source; link them in the PR description (1Password/Notion):
    //   // Source: <full name> <email> <consent date YYYY-MM-DD>
    static let entries: [FunnelTestimonial] = [
        // Source: <placeholder — replace>
        .init(
            id: 0,
            initials: "M.K.",
            persona: "Independent researcher",
            quote: "I used to grep 800 Obsidian notes by hand. Lumina actually finds what I asked about months ago. First AI that doesn't make me re-explain myself every conversation."
        ),
        // Source: <placeholder — replace>
        .init(
            id: 1,
            initials: "D.R.",
            persona: "Indie founder",
            quote: "My voice memos, my Safari saves, my Health data — Lumina sees them as one corpus. It reads back insights I would have lost otherwise."
        ),
        // Source: <placeholder — replace>
        .init(
            id: 2,
            initials: "S.T.",
            persona: "Knowledge worker",
            quote: "The SOUL.md voice thing sounded gimmicky until it wasn't. Lumina sounds like me writing to myself. Generic AI feels broken now."
        ),
    ]
}
