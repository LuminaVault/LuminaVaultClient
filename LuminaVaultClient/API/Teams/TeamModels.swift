import Foundation

struct TeamSpaceSummary: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let role: String
    let archivedAt: Date?
}

struct SharedVaultSummary: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let teamID: UUID?
    let name: String
    let isPersonal: Bool
    let role: String
    let canUseAI: Bool
    let archivedAt: Date?

    var canWrite: Bool {
        role == "editor" || role == "admin"
    }

    var canAdmin: Bool {
        role == "admin"
    }
}

struct VaultMemberSummary: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let userID: UUID
    let username: String
    let email: String
    let role: String
    let canUseAI: Bool
}

struct VaultActivitySummary: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let vaultID: UUID
    let actorUserID: UUID?
    let actorName: String
    let action: String
    let targetType: String
    let targetID: UUID?
    let targetTitle: String?
    let createdAt: Date
}

struct TeamInvitationSummary: Codable, Identifiable, Sendable {
    let id: UUID
    let teamID: UUID
    let email: String
    let expiresAt: Date
    let token: String?
}

struct TeamInviteGrant: Codable, Sendable {
    let role: String
    let canUseAI: Bool
}
