// LuminaVaultClient/LuminaVaultClient/API/Import/VaultImportEndpoints.swift
//
// Bulk vault import — POST /v1/import/vault-bulk. The iOS app reads a picked
// Obsidian vault folder locally and posts markdown straight to the proven
// server bulk-ingest endpoint (no zip/multipart needed). Field names are
// camelCase to match the server's default JSON decoder.

import Foundation

nonisolated struct VaultBulkFile: Encodable {
    let path: String
    let content: String
}

nonisolated struct VaultBulkRequest: Encodable {
    let space: String
    let files: [VaultBulkFile]
    /// `"skip"` leaves a different note already at a file's path alone and
    /// reports it `exists`; `"overwrite"` (the server default) replaces it.
    var onConflict: String?
}

/// What the server did with one input file.
nonisolated struct VaultBulkFileResult: Decodable, Equatable {
    let path: String
    let savedPath: String?
    /// imported, updated, unchanged, empty, hidden, unsupported, collision,
    /// exists or failed.
    let status: String
}

nonisolated struct VaultBulkResponse: Decodable {
    let spaceID: String
    let spaceSlug: String
    let imported: Int
    let skipped: Int
    let failed: Int
    /// Per-file outcomes; nil from a server older than the per-file report.
    var files: [VaultBulkFileResult]?
}

nonisolated enum VaultImportEndpoints {
    nonisolated struct Bulk: Endpoint {
        typealias Response = VaultBulkResponse
        let request: VaultBulkRequest
        var path: String { "/v1/import/vault-bulk" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }
}
