// LuminaVaultClient/LuminaVaultClient/Features/Community/CommunityPresentation.swift
//
// Pure rules for how a community post is shown and what may be done to it,
// and how server error codes read to a person. Kept out of the views so the
// rules are testable without rendering anything.

import Foundation
import LuminaVaultShared

nonisolated enum CommunityPresentation {
    /// The byline for AI posts. The server sends no profile for them.
    static let aiAuthorName = "LuminaVault"
    /// Fallback for an AI post that arrives without `aiLabel`.
    static let aiFallbackLabel = "AI-generated"

    static func isAI(_ post: CommunityPostDTO) -> Bool {
        post.author.kind == .ai || post.isDailyPost
    }

    static func authorName(_ post: CommunityPostDTO) -> String {
        if isAI(post) { return aiAuthorName }
        if let name = post.author.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let handle = post.author.handle, !handle.isEmpty { return "@\(handle)" }
        return "Member"
    }

    static func authorHandle(_ post: CommunityPostDTO) -> String? {
        guard !isAI(post), let handle = post.author.handle, !handle.isEmpty else { return nil }
        return "@\(handle)"
    }

    /// The AI caption, shown verbatim — the wording lives on the server.
    static func aiLabel(_ post: CommunityPostDTO) -> String? {
        guard isAI(post) else { return nil }
        if let label = post.aiLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        return aiFallbackLabel
    }

    /// "Awaiting review" — only the author ever receives their own pending
    /// posts, but the `isOwn` check keeps the badge honest regardless.
    static func showsPendingBadge(_ post: CommunityPostDTO) -> Bool {
        post.status == .pending && post.isOwn
    }

    /// Report and block are for other members' posts only — never your own,
    /// never the AI's (it has no profile to block).
    static func canReport(_ post: CommunityPostDTO) -> Bool {
        !post.isOwn && !isAI(post) && post.author.kind == .user
    }

    static func canBlock(_ post: CommunityPostDTO) -> Bool {
        canReport(post) && post.author.profileId != nil
    }

    static func canDelete(_ post: CommunityPostDTO) -> Bool {
        post.isOwn && !isAI(post)
    }

    static func reasonLabel(_ reason: CommunityReportReason) -> String {
        switch reason {
        case .spam: "Spam"
        case .harassment: "Harassment or bullying"
        case .hate: "Hate speech"
        case .sexual: "Sexual content"
        case .violence: "Violence or threats"
        case .selfHarm: "Self-harm"
        case .misinformation: "Misinformation"
        case .other: "Something else"
        }
    }
}

/// Composer gating, straight from `CommunityMeDTO`.
nonisolated enum CommunityComposeAccess: Equatable {
    /// The board is off; no entry point should be on screen at all.
    case boardDisabled
    /// Posting is paused for everyone (`postingEnabled == false`).
    case postingDisabled
    /// No profile yet, or the accepted terms are older than required.
    case needsProfile
    /// A moderator suspended this member's posting.
    case suspended(until: Date)
    case allowed

    init(me: CommunityMeDTO?, now: Date = Date()) {
        guard let me, me.enabled else { self = .boardDisabled; return }
        guard me.postingEnabled else { self = .postingDisabled; return }
        guard let profile = me.profile, profile.termsVersion >= me.termsVersionRequired else {
            self = .needsProfile
            return
        }
        if let until = profile.postingSuspendedUntil, until > now {
            self = .suspended(until: until)
            return
        }
        self = .allowed
    }
}

/// Server error codes → sentences. The community routes answer with
/// `{"error":{"message":"<code>"}}`; the code is in `message`.
nonisolated enum CommunityErrorMessage {
    static let guidelines = "This goes against the Community Guidelines, so it wasn't posted. "
        + "Please edit it and try again."

    /// The machine code the server sent, if any.
    static func code(for error: Error) -> String? {
        guard let structured = (error as? APIError)?.structuredError else { return nil }
        return structured.code.isEmpty ? structured.message : structured.code
    }

    static func text(for error: Error) -> String {
        if case APIError.rateLimited = error {
            return "You're doing that a little fast. Try again in a moment."
        }
        guard let code = code(for: error) else {
            return (error as? APIError)?.userFacingMessage ?? error.localizedDescription
        }
        if code.hasPrefix("moderation_rejected") { return guidelines }
        switch code {
        case "handle_taken":
            return "That handle is taken. Try another one."
        case "invalid_handle":
            return "Handles are 3–20 characters: lowercase letters, numbers and underscores."
        case "invalid_display_name":
            return "Display names are 1–40 characters and must follow the Community Guidelines."
        case "terms_required":
            return "Please agree to the Community Guidelines to continue."
        case "community_profile_required":
            return "Set up your community profile before posting."
        case "posting_suspended":
            return "Posting is paused on your account. Contact support if you think this is a mistake."
        case "daily_limit_reached":
            return "You've reached today's posting limit. Try again tomorrow."
        case "community_posting_disabled":
            return "Posting is paused for everyone right now. You can still read the board."
        case "community_disabled":
            return "The Community board isn't available right now."
        case "invalid_title":
            return "Titles are 3–120 characters."
        case "invalid_body":
            return "Posts are 1–4,000 characters."
        case "post_not_found":
            return "This post is no longer available."
        case "cannot_report_own_post":
            return "You can't report your own post."
        case "cannot_block_self":
            return "You can't block yourself."
        default:
            return (error as? APIError)?.userFacingMessage ?? error.localizedDescription
        }
    }

    /// True for codes that mean "go set up your profile first".
    static func needsProfile(_ error: Error) -> Bool {
        guard let code = code(for: error) else { return false }
        return code == "community_profile_required" || code == "terms_required"
    }
}

/// Hashable route into a thread. `CommunityPostDTO` is only `Equatable`, and
/// identity is all navigation needs.
nonisolated struct CommunityThreadRoute: Hashable, Identifiable, Sendable {
    let post: CommunityPostDTO
    var id: UUID { post.id }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
