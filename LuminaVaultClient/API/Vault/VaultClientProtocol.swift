// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultClientProtocol.swift
// HER-35: createVault + status for the post-auth gate.
// HER-105: list/read/move/delete for the in-app vault browser.
import Foundation

protocol VaultClientProtocol {
    func createVault() async throws -> VaultStatusResponse
    func status() async throws -> VaultStatusResponse

    // MARK: - HER-105 browser

    /// Paginated list of vault files for the authenticated tenant.
    /// `spaceSlug` filters by Space (HER-9 binding); `q` does a
    /// case-insensitive substring match on the file path.
    func listFiles(
        spaceSlug: String?,
        q: String?,
        before: Date?,
        after: Date?,
        limit: Int?
    ) async throws -> VaultFileListResponse

    /// Raw bytes for a single vault file. Returns (data, contentType).
    func readFile(relativePath: String) async throws -> (Data, String)

    func moveFile(from: String, to: String) async throws -> VaultFileDTO

    func deleteFile(relativePath: String) async throws
}
