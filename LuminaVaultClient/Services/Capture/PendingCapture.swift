// LuminaVaultClient/LuminaVaultClient/Services/Capture/PendingCapture.swift
//
// HER-34 — local persistence row for a queued photo capture. Survives
// app relaunches; consumed by `CaptureDrainer` when the network is up.

import Foundation
import SwiftData

/// State machine: row is created `pending`, retried up to `attempts ==
/// CaptureDrainer.maxAttempts`, then flipped to `failed` and surfaced in
/// a "review captures" badge for the user.
enum PendingCaptureState: String, Codable, Sendable {
    case pending
    case failed
}

/// HER-256 / HER-257 — discriminator added so the queue can host
/// non-photo captures. `.text` rows carry the body in `captionText` and
/// route to `POST /v1/memory/upsert`. `.url` (HER-257) rows carry the
/// URL in `urlString` and an optional note in `captionText`; the drainer
/// posts them to `POST /v1/capture/safari`. `.photo` (default) keeps the
/// original behaviour — rows persisted before this enum landed
/// deserialise with `.photo` because the SwiftData store falls back to
/// the default value of a new field.
enum PendingCaptureKind: String, Codable, Sendable {
    case photo
    case text
    case url
}

@Model
final class PendingCapture {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var captionText: String?
    /// Raw bytes from `PhotosPickerItem.loadTransferable(type: Data.self)`.
    /// HEIC and JPEG both pass through losslessly (HER-34 server allowlist).
    /// Empty `Data()` for `.text` rows (HER-256) since the queue stores
    /// the body in `captionText` and skips the upload step.
    var imageData: Data
    /// MIME the client sends in the upload `Content-Type` header (e.g.
    /// `image/heic`, `image/heif`, `image/jpeg`). Empty string for `.text`.
    var contentType: String
    /// File extension persisted as part of the vault path (e.g. `heic`,
    /// `jpg`). Decoupled from `contentType` because HEIF MIME still maps
    /// to `.heic` on disk. Empty string for `.text`.
    var fileExtension: String

    /// HER-256 — capture kind. Defaults to `.photo` so rows persisted
    /// before this field landed keep their original behaviour.
    var kindRaw: String = PendingCaptureKind.photo.rawValue

    var kind: PendingCaptureKind {
        get { PendingCaptureKind(rawValue: kindRaw) ?? .photo }
        set { kindRaw = newValue.rawValue }
    }

    /// HER-257 — populated only when `kind == .url`. The drainer reads
    /// this and posts to `/v1/capture/safari`; `captionText` carries the
    /// optional user note that ships as `notes` on the request.
    var urlString: String?

    // HER-207 geo anchor — all four optional, populated only when the
    // user toggled Location on for this capture.
    var lat: Double?
    var lng: Double?
    var accuracyM: Double?
    var placeName: String?

    /// HER-CaptureTab — optional Space association forwarded to
    /// `POST /v1/vault/files?space_id=…`. Adding the field as optional
    /// is safe under SwiftData lightweight migration: rows persisted
    /// before this change deserialise with `nil` and land unfiled.
    var spaceID: UUID?

    var attempts: Int
    var lastError: String?
    var stateRaw: String

    var state: PendingCaptureState {
        get { PendingCaptureState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        captionText: String? = nil,
        imageData: Data,
        contentType: String,
        fileExtension: String,
        lat: Double? = nil,
        lng: Double? = nil,
        accuracyM: Double? = nil,
        placeName: String? = nil,
        spaceID: UUID? = nil,
        kind: PendingCaptureKind = .photo,
        urlString: String? = nil,
        attempts: Int = 0,
        lastError: String? = nil,
        state: PendingCaptureState = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.captionText = captionText
        self.imageData = imageData
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.lat = lat
        self.lng = lng
        self.accuracyM = accuracyM
        self.placeName = placeName
        self.spaceID = spaceID
        self.kindRaw = kind.rawValue
        self.urlString = urlString
        self.attempts = attempts
        self.lastError = lastError
        self.stateRaw = state.rawValue
    }
}
