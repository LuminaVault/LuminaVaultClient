// LuminaVaultClient/LuminaVaultClient/Services/AppGroup/PendingShare.swift
//
// Wire shape the Share Extension writes into the App Group. Main app
// reads on launch/foreground, replays each row into the capture pipeline,
// then removes only successfully handled rows.

import Foundation

enum PendingShareKind: String, Codable, Sendable {
    case url
    case text
    case image
}

struct PendingShare: Codable, Sendable, Equatable {
    /// Stable id so the main app can dedupe if both targets somehow
    /// touch the queue in the same launch cycle.
    let id: UUID
    let kind: PendingShareKind
    let url: String?
    let text: String?
    let note: String?
    let spaceID: UUID?
    let capturedAt: Date
    /// Relative file name under `pendingShareAssets/` for queued image
    /// attachments. URL/text rows keep this nil.
    let assetFileName: String?
    let contentType: String?
    let fileExtension: String?

    init(
        id: UUID = UUID(),
        url: String,
        note: String? = nil,
        spaceID: UUID? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.kind = .url
        self.url = url
        self.text = nil
        self.note = note
        self.spaceID = spaceID
        self.capturedAt = capturedAt
        self.assetFileName = nil
        self.contentType = nil
        self.fileExtension = nil
    }

    init(
        id: UUID = UUID(),
        text: String,
        note: String? = nil,
        spaceID: UUID? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.kind = .text
        self.url = nil
        self.text = text
        self.note = note
        self.spaceID = spaceID
        self.capturedAt = capturedAt
        self.assetFileName = nil
        self.contentType = "text/markdown"
        self.fileExtension = "md"
    }

    init(
        id: UUID = UUID(),
        imageAssetFileName: String,
        contentType: String,
        fileExtension: String,
        note: String? = nil,
        spaceID: UUID? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.kind = .image
        self.url = nil
        self.text = nil
        self.note = note
        self.spaceID = spaceID
        self.capturedAt = capturedAt
        self.assetFileName = imageAssetFileName
        self.contentType = contentType
        self.fileExtension = fileExtension
    }
}

/// Lightweight Space snapshot the main app writes for the extension's
/// picker. Mirrors `LuminaVaultShared.SpaceDTO` but pares it down to the
/// fields the picker UI needs so the App Group payload stays small.
struct SharedSpaceSummary: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
}
