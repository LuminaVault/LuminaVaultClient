// LuminaVaultClient/LuminaVaultClient/API/Import/VaultNotionImportDTO.swift
// Backlog E7.4: Notion import on iOS (spec 2026-11-18, D7/D8 and the "Wire
// contract" section). Mirrors the Go spec's `VaultNotionImportReport`, the
// 200 body of `POST /v1/vault/import/notion` (op `vaultImportNotion`).
// Client-local like the other Go-era vault DTOs (history, trash, links,
// properties): LuminaVaultShared mirrors the archived Swift server, which
// never had this route.
//
// Keys are camelCase on the wire. `JSONDecoder.hvDefault` converts from
// snake_case, which leaves camelCase keys as they are, so `spaceId` needs an
// explicit coding key to land on `spaceID`. Every field is decoded with a
// default: a dry run omits `spaceId` and view ids, the lists are empty while
// `VAULT_PROPERTIES_ENABLED` is off, and a report that gains or drops a field
// must still render.
import Foundation

nonisolated struct VaultNotionImportReport: Decodable, Sendable, Equatable {
    var dryRun: Bool
    /// Absent on a dry run when the Space does not exist yet.
    var spaceID: String?
    var spaceSlug: String?
    var pages: Int
    var databases: Int
    var rows: Int
    var attachments: Int
    var written: Int
    var skipped: Int
    var failed: Int
    var links: Links
    /// The inferred type of each database column.
    var columns: [Column]
    var views: [SavedView]
    var collisions: [Collision]
    /// At most 5,000 entries.
    var files: [File]
    var warnings: [String]

    nonisolated struct Links: Decodable, Sendable, Equatable {
        var resolved: Int
        var external: Int
        var unresolved: Int
        /// At most 50 entries; `unresolved` is the full count.
        var unresolvedList: [Unresolved]

        init(resolved: Int = 0, external: Int = 0, unresolved: Int = 0, unresolvedList: [Unresolved] = []) {
            self.resolved = resolved
            self.external = external
            self.unresolved = unresolved
            self.unresolvedList = unresolvedList
        }

        private enum CodingKeys: String, CodingKey {
            case resolved, external, unresolved, unresolvedList
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            resolved = try c.decodeIfPresent(Int.self, forKey: .resolved) ?? 0
            external = try c.decodeIfPresent(Int.self, forKey: .external) ?? 0
            unresolved = try c.decodeIfPresent(Int.self, forKey: .unresolved) ?? 0
            unresolvedList = try c.decodeIfPresent([Unresolved].self, forKey: .unresolvedList) ?? []
        }
    }

    /// Every field of the list elements is optional: one odd element among
    /// 5,000 must not fail the report of an import that already happened.
    nonisolated struct Unresolved: Decodable, Sendable, Equatable {
        var page: String?
        var target: String?
    }

    nonisolated struct Column: Decodable, Sendable, Equatable {
        var database: String?
        var name: String?
        var type: String?
    }

    /// A saved view the import created for a database. Not named `View`:
    /// that would shadow SwiftUI's inside any extension of the report.
    nonisolated struct SavedView: Decodable, Sendable, Equatable {
        /// Absent on a dry run.
        var id: String?
        var name: String?
        var folder: String?
    }

    nonisolated struct Collision: Decodable, Sendable, Equatable {
        var from: String?
        var to: String?
    }

    nonisolated struct File: Decodable, Sendable, Equatable {
        var entry: String?
        var savedPath: String?
        /// `page`, `row`, `attachment`, `database` or `other`. Kept a string so
        /// a kind the server adds later still decodes.
        var kind: String?
        /// `imported`, `updated`, `unchanged`, `exists`, `empty`, `tooLarge`,
        /// `hidden`, `unsupported`, `failed`, or `planned` on a dry run.
        var status: String?
    }

    init(
        dryRun: Bool,
        spaceID: String? = nil,
        spaceSlug: String? = nil,
        pages: Int = 0,
        databases: Int = 0,
        rows: Int = 0,
        attachments: Int = 0,
        written: Int = 0,
        skipped: Int = 0,
        failed: Int = 0,
        links: Links = Links(),
        columns: [Column] = [],
        views: [SavedView] = [],
        collisions: [Collision] = [],
        files: [File] = [],
        warnings: [String] = [],
    ) {
        self.dryRun = dryRun
        self.spaceID = spaceID
        self.spaceSlug = spaceSlug
        self.pages = pages
        self.databases = databases
        self.rows = rows
        self.attachments = attachments
        self.written = written
        self.skipped = skipped
        self.failed = failed
        self.links = links
        self.columns = columns
        self.views = views
        self.collisions = collisions
        self.files = files
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case dryRun
        case spaceID = "spaceId"
        case spaceSlug, pages, databases, rows, attachments, written, skipped, failed
        case links, columns, views, collisions, files, warnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dryRun = try c.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
        spaceID = try c.decodeIfPresent(String.self, forKey: .spaceID)
        spaceSlug = try c.decodeIfPresent(String.self, forKey: .spaceSlug)
        pages = try c.decodeIfPresent(Int.self, forKey: .pages) ?? 0
        databases = try c.decodeIfPresent(Int.self, forKey: .databases) ?? 0
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 0
        attachments = try c.decodeIfPresent(Int.self, forKey: .attachments) ?? 0
        written = try c.decodeIfPresent(Int.self, forKey: .written) ?? 0
        skipped = try c.decodeIfPresent(Int.self, forKey: .skipped) ?? 0
        failed = try c.decodeIfPresent(Int.self, forKey: .failed) ?? 0
        links = try c.decodeIfPresent(Links.self, forKey: .links) ?? Links()
        columns = try c.decodeIfPresent([Column].self, forKey: .columns) ?? []
        views = try c.decodeIfPresent([SavedView].self, forKey: .views) ?? []
        collisions = try c.decodeIfPresent([Collision].self, forKey: .collisions) ?? []
        files = try c.decodeIfPresent([File].self, forKey: .files) ?? []
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}
