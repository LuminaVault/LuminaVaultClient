// LuminaVaultClient/LuminaVaultClient/Services/AppGroup/PendingShare.swift
//
// HER-258 — wire shape the Share Extension writes into the App Group.
// Main app reads at launch, enqueues each row into `CaptureQueue` as a
// `.url` snapshot, then deletes the file.

import Foundation

struct PendingShare: Codable, Sendable, Equatable {
    /// Stable id so the main app can dedupe if both targets somehow
    /// touch the queue in the same launch cycle.
    let id: UUID
    let url: String
    let note: String?
    let spaceID: UUID?
    let capturedAt: Date

    init(
        id: UUID = UUID(),
        url: String,
        note: String? = nil,
        spaceID: UUID? = nil,
        capturedAt: Date = Date(),
    ) {
        self.id = id
        self.url = url
        self.note = note
        self.spaceID = spaceID
        self.capturedAt = capturedAt
    }
}

/// Lightweight Space snapshot the main app writes for the extension's
/// picker. Mirrors `LuminaVaultShared.SpaceDTO` but pares it down to the
/// fields the picker UI needs so the App Group payload stays small.
struct SharedSpaceSummary: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
}
