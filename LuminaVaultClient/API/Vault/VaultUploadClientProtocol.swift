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

    /// HER-Notes — write a note (`?note=true&processed=true`). The server
    /// owns the recall memory for the file: it creates-or-updates the linked
    /// memory and re-embeds in the same call, so an edit is instantly current
    /// in chat (no separate `/v1/memory/upsert`). `metadata` rides the
    /// `X-Vault-Metadata` header (title, tags, isTodo, done, dueAt).
    func uploadNote(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?,
        metadata: VaultNoteMetadataDTO?
    ) async throws -> VaultUploadResponse

    /// Backlog E5.4: the same write, sent with `If-Match` so a save made from
    /// a stale version fails with 412 instead of overwriting.
    func uploadNote(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?,
        metadata: VaultNoteMetadataDTO?,
        ifMatch: String?
    ) async throws -> VaultUploadResponse

    /// Markdown import: a note write sent with `If-None-Match: *`, so it is
    /// create-only and a name that is already taken answers 412 instead of
    /// replacing that note.
    func createNote(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?
    ) async throws -> VaultUploadResponse

    /// Saves an edit over a note that already exists, at its own path and in
    /// its own Space, at any folder depth (`PUT /v1/vault/files/{path}`).
    /// Upload keeps only the base name under the Space's folder, so saving a
    /// nested note (an imported `lore/people/ada.md`) through it wrote a
    /// second copy at `lore/ada.md`. Same note flags, sidecar and `If-Match`.
    func replaceNote(
        data: Data,
        contentType: String,
        relativePath: String,
        metadata: VaultNoteMetadataDTO?,
        ifMatch: String?
    ) async throws -> VaultUploadResponse
}

extension VaultUploadClientProtocol {
    /// Default is the plain note write so existing stubs keep working; the
    /// HTTP client overrides it with the in-place `PUT`.
    func replaceNote(
        data: Data,
        contentType: String,
        relativePath: String,
        metadata: VaultNoteMetadataDTO?,
        ifMatch: String?
    ) async throws -> VaultUploadResponse {
        try await uploadNote(
            data: data, contentType: contentType, relativePath: relativePath,
            spaceID: nil, metadata: metadata, ifMatch: ifMatch,
        )
    }

    /// Default is a plain note write so existing stubs keep working; the HTTP
    /// client overrides it with the create-only header.
    func createNote(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?
    ) async throws -> VaultUploadResponse {
        try await uploadNote(
            data: data, contentType: contentType,
            relativePath: relativePath, spaceID: spaceID, metadata: nil,
        )
    }

    /// Default ignores `ifMatch` so existing stubs keep working; the HTTP
    /// client overrides it.
    func uploadNote(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?,
        metadata: VaultNoteMetadataDTO?,
        ifMatch _: String?
    ) async throws -> VaultUploadResponse {
        try await uploadNote(
            data: data, contentType: contentType,
            relativePath: relativePath, spaceID: spaceID, metadata: metadata,
        )
    }

    func uploadAsset(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?,
        processed _: Bool
    ) async throws -> VaultUploadResponse {
        try await uploadAsset(data: data, contentType: contentType, relativePath: relativePath, spaceID: spaceID)
    }

    /// Default forwards to the processed upload so existing stubs/conformers
    /// keep working; the HTTP client overrides with the real note wiring.
    func uploadNote(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?,
        metadata _: VaultNoteMetadataDTO?
    ) async throws -> VaultUploadResponse {
        try await uploadAsset(
            data: data, contentType: contentType,
            relativePath: relativePath, spaceID: spaceID, processed: true,
        )
    }
}
