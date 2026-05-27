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
    let spaceID: UUID?
    let kind: PendingCaptureKind
    /// HER-257 — populated only when `kind == .url`.
    let urlString: String?

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
        urlString: String? = nil
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
        self.kind = kind
        self.urlString = urlString
    }

    /// HER-256 — convenience for text-only memory captures. Leaves the
    /// photo-specific fields empty; the drainer routes `.text` rows
    /// straight to `MemoryHTTPClient.upsert` and skips the vault upload.
    static func text(
        id: UUID = UUID(),
        body: String,
        createdAt: Date = .now,
        lat: Double? = nil,
        lng: Double? = nil,
        accuracyM: Double? = nil,
        placeName: String? = nil
    ) -> CaptureSnapshot {
        CaptureSnapshot(
            id: id,
            createdAt: createdAt,
            captionText: body,
            imageData: Data(),
            contentType: "",
            fileExtension: "",
            lat: lat,
            lng: lng,
            accuracyM: accuracyM,
            placeName: placeName,
            spaceID: nil,
            kind: .text,
        )
    }

    /// Share-extension text capture that must preserve Space association.
    /// The drainer uploads the body as markdown to the vault, then upserts
    /// memory content for search continuity.
    static func textFile(
        id: UUID = UUID(),
        body: String,
        note: String? = nil,
        spaceID: UUID? = nil,
        createdAt: Date = .now
    ) -> CaptureSnapshot {
        let rendered = Self.renderSharedText(body: body, note: note)
        return CaptureSnapshot(
            id: id,
            createdAt: createdAt,
            captionText: body,
            imageData: Data(rendered.utf8),
            contentType: "text/markdown",
            fileExtension: "md",
            spaceID: spaceID,
            kind: .textFile,
        )
    }

    /// HER-257 — convenience for URL/link captures. Drainer posts these
    /// to `POST /v1/capture/safari` (HER-149) which enriches asynchronously
    /// (OG / oEmbed / X scrape) and persists a vault file.
    static func url(
        id: UUID = UUID(),
        url: String,
        note: String? = nil,
        spaceID: UUID? = nil,
        createdAt: Date = .now
    ) -> CaptureSnapshot {
        CaptureSnapshot(
            id: id,
            createdAt: createdAt,
            captionText: note?.isEmpty == true ? nil : note,
            imageData: Data(),
            contentType: "",
            fileExtension: "",
            spaceID: spaceID,
            kind: .url,
            urlString: url,
        )
    }

    static func renderSharedText(body: String, note: String?) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedNote, !trimmedNote.isEmpty else { return trimmedBody + "\n" }
        return "\(trimmedNote)\n\n---\n\n\(trimmedBody)\n"
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
    let spaceID: UUID?
    let kind: PendingCaptureKind
    let urlString: String?
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
            spaceID: snapshot.spaceID,
            kind: snapshot.kind,
            urlString: snapshot.urlString,
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
                spaceID: row.spaceID,
                kind: row.kind,
                urlString: row.urlString,
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
