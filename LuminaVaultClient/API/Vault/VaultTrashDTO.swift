// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultTrashDTO.swift
// Backlog E3.4: GET /v1/vault/trash. A delete moves the file to the trash for
// 30 days (server `VaultTrashPurge`). Mirrors the Go spec's `VaultTrashItem` and
// `VaultTrashListResponse`; keys are camelCase, which `JSONDecoder.hvDefault`'s
// convertFromSnakeCase leaves untouched.
import Foundation

nonisolated struct VaultTrashItem: Decodable, Sendable, Equatable, Identifiable {
    let id: UUID
    /// Where the file was before it was deleted.
    let path: String
    let contentType: String
    let sizeBytes: Int64
    let spaceId: UUID?
    let title: String?
    let deletedAt: Date

    init(id: UUID = UUID(), path: String, contentType: String = "text/markdown", sizeBytes: Int64 = 0,
         spaceId: UUID? = nil, title: String? = nil, deletedAt: Date) {
        self.id = id
        self.path = path
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.spaceId = spaceId
        self.title = title
        self.deletedAt = deletedAt
    }

    static let retentionDays = 30

    /// Whole days until the server deletes it for good; never below zero.
    func daysLeft(now: Date = Date()) -> Int {
        let expiry = deletedAt.addingTimeInterval(TimeInterval(Self.retentionDays) * 86_400)
        let left = expiry.timeIntervalSince(now) / 86_400
        return max(0, Int(left.rounded(.up)))
    }
}

nonisolated struct VaultTrashListResponse: Decodable, Sendable, Equatable {
    let items: [VaultTrashItem]
}
