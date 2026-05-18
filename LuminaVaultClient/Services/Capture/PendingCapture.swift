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

@Model
final class PendingCapture {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var captionText: String?
    /// Raw bytes from `PhotosPickerItem.loadTransferable(type: Data.self)`.
    /// HEIC and JPEG both pass through losslessly (HER-34 server allowlist).
    var imageData: Data
    /// MIME the client sends in the upload `Content-Type` header (e.g.
    /// `image/heic`, `image/heif`, `image/jpeg`).
    var contentType: String
    /// File extension persisted as part of the vault path (e.g. `heic`,
    /// `jpg`). Decoupled from `contentType` because HEIF MIME still maps
    /// to `.heic` on disk.
    var fileExtension: String

    // HER-207 geo anchor — all four optional, populated only when the
    // user toggled Location on for this capture.
    var lat: Double?
    var lng: Double?
    var accuracyM: Double?
    var placeName: String?

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
        self.attempts = attempts
        self.lastError = lastError
        self.stateRaw = state.rawValue
    }
}
