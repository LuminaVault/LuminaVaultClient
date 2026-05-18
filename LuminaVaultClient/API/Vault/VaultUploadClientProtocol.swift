// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultUploadClientProtocol.swift
//
// HER-34 — raw-body upload seam for vault assets (HEIC / JPEG / PNG /
// markdown). Lives next to `VaultClientProtocol` (HER-35 / HER-105) but
// stays a separate protocol because the upload path is binary and the
// other surface is JSON only.

import Foundation
import LuminaVaultShared

protocol VaultUploadClientProtocol: Sendable {
    /// POST /v1/vault/files?path=<relativePath>
    /// Body is the raw asset bytes; `Content-Type` must match the file
    /// extension per the server allowlist (HER-34 adds heic + heif).
    func uploadAsset(
        data: Data,
        contentType: String,
        relativePath: String
    ) async throws -> VaultUploadResponse
}
