// LuminaVaultClient/LuminaVaultClient/API/Import/VaultImportEndpoints.swift
//
// Bulk vault import — POST /v1/import/vault-bulk. The iOS app reads a picked
// Obsidian vault folder locally and posts markdown straight to the proven
// server bulk-ingest endpoint (no zip/multipart needed). Field names are
// camelCase to match the server's default JSON decoder.

import Foundation

struct VaultBulkFile: Encodable {
    let path: String
    let content: String
}

struct VaultBulkRequest: Encodable {
    let space: String
    let files: [VaultBulkFile]
}

struct VaultBulkResponse: Decodable {
    let spaceID: String
    let spaceSlug: String
    let imported: Int
    let skipped: Int
    let failed: Int
}

enum VaultImportEndpoints {
    struct Bulk: Endpoint {
        typealias Response = VaultBulkResponse
        let request: VaultBulkRequest
        var path: String { "/v1/import/vault-bulk" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }
}
