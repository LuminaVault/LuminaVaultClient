// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultUploadClientProtocol.swift
//
// HER-34 — raw-body upload seam for vault assets (HEIC / JPEG / PNG /
// markdown). Lives next to `VaultClientProtocol` (HER-35 / HER-105) but
// stays a separate protocol because the upload path is binary and the
// other surface is JSON only.

import Foundation
import LuminaVaultShared

protocol VaultUploadClientProtocol: Sendable {
    /// POST /v1/vault/files?path=<relativePath>[&space_id=<uuid>]
    /// Body is the raw asset bytes; `Content-Type` must match the file
    /// extension per the server allowlist (HER-34 adds heic + heif).
    /// `spaceID` (HER-CaptureTab) optionally associates the vault_files
    /// row with a Space the caller owns. Pass nil to leave the file
    /// unfiled. Cross-tenant or malformed UUIDs raise 400 server-side.
    func uploadAsset(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?
    ) async throws -> VaultUploadResponse

    /// HER-105 — same upload, but `processed: true` marks the row already
    /// compiled (`?processed=true`) so Sync & Learn skips it. Written text
    /// notes use this because they create their memory immediately via
    /// `/v1/memory/upsert`; the markdown file is just for visibility. A default
    /// implementation forwards to the base call so existing conformers/stubs
    /// keep working; the real HTTP client overrides it.
    func uploadAsset(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?,
        processed: Bool
    ) async throws -> VaultUploadResponse
}

extension VaultUploadClientProtocol {
    func uploadAsset(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?,
        processed _: Bool
    ) async throws -> VaultUploadResponse {
        try await uploadAsset(data: data, contentType: contentType, relativePath: relativePath, spaceID: spaceID)
    }
}
