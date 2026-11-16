// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultHistoryDTO.swift
// Backlog E4.5: GET /v1/vault/history. The server keeps a git history per
// vault (E4.3); this lists the versions of one file. Mirrors the Go spec's
// `VaultHistoryVersion` and `VaultHistoryResponse`; keys are camelCase.
import Foundation

nonisolated struct VaultHistoryVersion: Decodable, Sendable, Equatable, Identifiable {
    let sha: String
    let committedAt: Date
    /// The commit subject, e.g. "upload: inbox/a.md".
    let message: String
    /// upload, move, delete, restore, import, sweep, …
    let reason: String
    let actorId: UUID?
    let sizeBytes: Int64
    /// This version removed the file.
    let deleted: Bool

    var id: String {
        sha
    }

    init(
        sha: String,
        committedAt: Date,
        message: String = "",
        reason: String = "upload",
        actorId: UUID? = nil,
        sizeBytes: Int64 = 0,
        deleted: Bool = false
    ) {
        self.sha = sha
        self.committedAt = committedAt
        self.message = message
        self.reason = reason
        self.actorId = actorId
        self.sizeBytes = sizeBytes
        self.deleted = deleted
    }

    /// What the reason means to a reader. Unknown reasons read as "Saved".
    var reasonLabel: String {
        if deleted {
            return "Deleted"
        }
        switch reason {
        case "move": return "Moved or renamed"
        case "delete": return "Deleted"
        case "restore": return "Restored"
        case "import": return "Imported"
        case "todo": return "Task updated"
        case "capture": return "Captured"
        case "skill": return "Written by a skill"
        case "soul": return "Personality updated"
        case "pull": return "Synced from GitHub"
        case "init": return "History started"
        default: return "Saved"
        }
    }
}

nonisolated struct VaultHistoryResponse: Decodable, Sendable, Equatable {
    let versions: [VaultHistoryVersion]
}
