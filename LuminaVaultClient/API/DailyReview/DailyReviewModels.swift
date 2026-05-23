// LuminaVaultClient/LuminaVaultClient/API/DailyReview/DailyReviewModels.swift
//
// HER-154 scaffold — local mirror of the server's MeTodayResponse shape
// (HER-206). The server schema (LuminaVaultServer/Sources/AppAPI/openapi.yaml)
// is:
//   { date, memories: [MemoryDTO], achievements: [AchievementDTO],
//     soulExcerpt: String, suggestedActions: [String] }
//
// TODO(HER-154-shared): once `MeTodayResponse` is added to
// `LuminaVaultShared/Sources/LuminaVaultShared/APIDTOs.swift`, replace
// this file with a typealias re-export (see `API/Conversations/
// ConversationsModels.swift` for the established pattern) and delete
// the local structs. Until then we trade strict DTO-singleness for an
// unblocked scaffold — the wire shape is captured by these stand-ins.
import Foundation
import LuminaVaultShared

struct DailyReviewDigest: Codable, Sendable, Equatable {
    let date: Date
    /// Memory rows representing this week's memos. Uses the existing
    /// `QueryHitDTO` shape (id + content + distance + createdAt) — the
    /// daily-brief job emits the same field set so we don't pay for a
    /// second DTO until a richer "memo summary" type is needed.
    let memories: [QueryHitDTO]
    let achievements: [DailyReviewAchievement]
    let soulExcerpt: String
    let suggestedActions: [String]
    /// HER-154 — streak length in days, derived server-side from the
    /// daily-brief job. Not yet in the openapi schema; placeholder so the
    /// view can render the counter without conditional plumbing.
    let streakDays: Int?
    /// HER-154 — "Hermes' reflection of the day" text. Distinct from
    /// `soulExcerpt` (which is the user's own SOUL.md slice); reflection
    /// is server-generated coaching copy.
    let reflection: String?

    init(
        date: Date,
        memories: [QueryHitDTO] = [],
        achievements: [DailyReviewAchievement] = [],
        soulExcerpt: String = "",
        suggestedActions: [String] = [],
        streakDays: Int? = nil,
        reflection: String? = nil,
    ) {
        self.date = date
        self.memories = memories
        self.achievements = achievements
        self.soulExcerpt = soulExcerpt
        self.suggestedActions = suggestedActions
        self.streakDays = streakDays
        self.reflection = reflection
    }
}

/// Light wrapper over the achievement subset the daily review needs.
/// Mirrors `AchievementDTO` fields used by the digest; the full
/// `AchievementsResponse` lives in `LuminaVaultShared` already and can
/// replace this once the full DTO surfaces here.
struct DailyReviewAchievement: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let unlockedAt: Date?

    init(id: String, title: String, unlockedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.unlockedAt = unlockedAt
    }
}

