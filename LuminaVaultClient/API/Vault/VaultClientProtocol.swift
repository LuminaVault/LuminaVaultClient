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

    /// HER-212 — streams `GET /v1/vault/export` (tar.gz of the user's vault).
    /// Returns the archive bytes plus the response `Content-Type`. Caller is
    /// responsible for spilling to disk and surfacing the share sheet.
    func exportVault() async throws -> (Data, String)

    /// Backlog E2.2 — `GET /v1/vault/links/{id}`: what a note links to and
    /// which notes link to it.
    func documentLinks(vaultFileID: UUID) async throws -> VaultLinksResponse

    /// Backlog E3.4 — deleted files that can still be restored, newest first.
    func listTrash() async throws -> [VaultTrashItem]
    /// Puts a trashed file back; the server may give it a new name when the
    /// old path is taken. A 410 means the file is gone for good.
    func restoreTrash(id: UUID) async throws -> VaultFileDTO
    func deleteTrashForever(id: UUID) async throws

    /// Backlog E4.5 — the saved versions of one file, newest first. Empty
    /// when history is off on the server.
    func history(path: String) async throws -> [VaultHistoryVersion]
    /// The file's bytes at one version. Returns (data, contentType).
    func readVersion(sha: String, path: String) async throws -> (Data, String)
    /// Writes the file back as it was at `sha`, as a new version. `ifMatch`
    /// is the on-screen version; a 412 means it changed on another device.
    func restoreVersion(sha: String, path: String, ifMatch: String?) async throws -> VaultFileDTO

    /// Backlog E6.4 — today's note in `tz`, created from the user's daily
    /// template when it doesn't exist yet. Safe to call from two devices.
    func dailyNote(tz: String?) async throws -> VaultFileDTO
    /// Writes the starter templates that are missing; never overwrites.
    func seedTemplates() async throws -> VaultTemplatesSeedResponse
    /// A new note rendered from a template. 409 when the name is taken.
    func noteFromTemplate(_ request: VaultFromTemplateRequest) async throws -> VaultFileDTO
}

extension VaultClientProtocol {
    /// Fakes and previews that don't script links get an empty panel's error
    /// state rather than a compile error; `VaultHTTPClient` implements it.
    func documentLinks(vaultFileID _: UUID) async throws -> VaultLinksResponse {
        throw URLError(.unsupportedURL)
    }

    func listTrash() async throws -> [VaultTrashItem] { throw URLError(.unsupportedURL) }
    func restoreTrash(id _: UUID) async throws -> VaultFileDTO { throw URLError(.unsupportedURL) }
    func deleteTrashForever(id _: UUID) async throws { throw URLError(.unsupportedURL) }

    func history(path _: String) async throws -> [VaultHistoryVersion] { throw URLError(.unsupportedURL) }
    func readVersion(sha _: String, path _: String) async throws -> (Data, String) {
        throw URLError(.unsupportedURL)
    }
    func restoreVersion(sha _: String, path _: String, ifMatch _: String?) async throws -> VaultFileDTO {
        throw URLError(.unsupportedURL)
    }

    func dailyNote(tz _: String?) async throws -> VaultFileDTO { throw URLError(.unsupportedURL) }
    func seedTemplates() async throws -> VaultTemplatesSeedResponse { throw URLError(.unsupportedURL) }
    func noteFromTemplate(_: VaultFromTemplateRequest) async throws -> VaultFileDTO {
        throw URLError(.unsupportedURL)
    }
}
