// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultHTTPClient.swift
import Foundation

final class VaultHTTPClient: VaultClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func createVault() async throws -> VaultStatusResponse {
        try await client.execute(VaultEndpoints.Create())
    }

    func status() async throws -> VaultStatusResponse {
        try await client.execute(VaultEndpoints.Status())
    }

    // MARK: - HER-105

    func listFiles(
        spaceSlug: String?,
        q: String?,
        before: Date?,
        after: Date?,
        limit: Int?
    ) async throws -> VaultFileListResponse {
        try await client.execute(VaultEndpoints.ListFiles(
            spaceSlug: spaceSlug, q: q, before: before, after: after, limit: limit,
        ))
    }

    func readFile(relativePath: String) async throws -> (Data, String) {
        let escaped = VaultEndpoints.DeleteFile.escape(relativePath)
        return try await client.fetchBytes(path: "/v1/vault/files/\(escaped)")
    }

    func moveFile(from: String, to: String) async throws -> VaultFileDTO {
        try await client.execute(VaultEndpoints.MoveFile(from: from, to: to))
    }

    func deleteFile(relativePath: String) async throws {
        _ = try await client.execute(VaultEndpoints.DeleteFile(relativePath: relativePath))
    }

    // HER-212 — binary tar.gz response, so go through fetchBytes rather than
    // the JSON Endpoint pipeline. Returns the raw archive + Content-Type.
    func exportVault() async throws -> (Data, String) {
        try await client.fetchBytes(path: "/v1/vault/export")
    }
}
