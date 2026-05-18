// LuminaVaultClient/LuminaVaultClient/Services/Capture/CaptureQueue.swift
//
// HER-34 — actor wrapping the `PendingCapture` ModelContainer. Public
// API is enqueue / pending / delete / markFailure. The actor instantiates
// a fresh `ModelContext` per call (ModelContext is non-Sendable; storing
// one across `await` would crash under strict concurrency).

import Foundation
import SwiftData

protocol CaptureQueueProtocol: Sendable {
    func enqueue(_ snapshot: CaptureSnapshot) async throws
    func pending() async throws -> [CaptureRowSnapshot]
    func delete(id: UUID) async throws
    func markFailure(id: UUID, error: String, flipToFailed: Bool) async throws
    func count() async throws -> Int
}

/// Inbound enqueue payload. Reference-types like SwiftData `@Model`
/// instances can't cross actor boundaries, so the public API takes
/// value-typed snapshots.
struct CaptureSnapshot: Sendable {
    let id: UUID
    let createdAt: Date
    let captionText: String?
    let imageData: Data
    let contentType: String
    let fileExtension: String
    let lat: Double?
    let lng: Double?
    let accuracyM: Double?
    let placeName: String?

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
        placeName: String? = nil
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
    }
}

/// Outbound row snapshot — what the drainer iterates. Avoids handing
/// out the live `@Model` reference.
struct CaptureRowSnapshot: Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    let captionText: String?
    let imageData: Data
    let contentType: String
    let fileExtension: String
    let lat: Double?
    let lng: Double?
    let accuracyM: Double?
    let placeName: String?
    let attempts: Int
}

actor CaptureQueue: CaptureQueueProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// Convenience initializer used by the production app — creates an
    /// on-disk SwiftData store for `PendingCapture` rows. Tests use the
    /// in-memory `ModelConfiguration` overload below.
    static func makeProductionContainer() throws -> ModelContainer {
        try ModelContainer(for: PendingCapture.self)
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: PendingCapture.self, configurations: config)
    }

    func enqueue(_ snapshot: CaptureSnapshot) async throws {
        let ctx = ModelContext(container)
        let row = PendingCapture(
            id: snapshot.id,
            createdAt: snapshot.createdAt,
            captionText: snapshot.captionText,
            imageData: snapshot.imageData,
            contentType: snapshot.contentType,
            fileExtension: snapshot.fileExtension,
            lat: snapshot.lat,
            lng: snapshot.lng,
            accuracyM: snapshot.accuracyM,
            placeName: snapshot.placeName,
        )
        ctx.insert(row)
        try ctx.save()
    }

    func pending() async throws -> [CaptureRowSnapshot] {
        let ctx = ModelContext(container)
        let pendingRaw = PendingCaptureState.pending.rawValue
        let descriptor = FetchDescriptor<PendingCapture>(
            predicate: #Predicate { $0.stateRaw == pendingRaw },
            sortBy: [SortDescriptor(\.createdAt)],
        )
        let rows = try ctx.fetch(descriptor)
        return rows.map { row in
            CaptureRowSnapshot(
                id: row.id,
                createdAt: row.createdAt,
                captionText: row.captionText,
                imageData: row.imageData,
                contentType: row.contentType,
                fileExtension: row.fileExtension,
                lat: row.lat,
                lng: row.lng,
                accuracyM: row.accuracyM,
                placeName: row.placeName,
                attempts: row.attempts,
            )
        }
    }

    func delete(id: UUID) async throws {
        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<PendingCapture>(
            predicate: #Predicate { $0.id == id },
        )
        if let row = try ctx.fetch(descriptor).first {
            ctx.delete(row)
            try ctx.save()
        }
    }

    func markFailure(id: UUID, error: String, flipToFailed: Bool) async throws {
        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<PendingCapture>(
            predicate: #Predicate { $0.id == id },
        )
        guard let row = try ctx.fetch(descriptor).first else { return }
        row.attempts += 1
        row.lastError = error
        if flipToFailed {
            row.stateRaw = PendingCaptureState.failed.rawValue
        }
        try ctx.save()
    }

    func count() async throws -> Int {
        let ctx = ModelContext(container)
        return try ctx.fetchCount(FetchDescriptor<PendingCapture>())
    }
}
