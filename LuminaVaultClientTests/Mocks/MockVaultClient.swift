// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockVaultClient.swift
// HER-35 — scripted VaultClientProtocol fake for CreateVaultViewModel tests.

@testable import LuminaVaultClient
import Foundation

final class MockVaultClient: VaultClientProtocol, @unchecked Sendable {
    var createResult: Result<VaultStatusResponse, Error> = .success(
        VaultStatusResponse(initialized: true, createdAt: Date(timeIntervalSince1970: 0), defaultSpaceSlugs: ["ai", "stocks", "health", "work", "ideas"])
    )
    var statusResult: Result<VaultStatusResponse, Error> = .success(
        VaultStatusResponse(initialized: false)
    )

    private(set) var calls: [Call] = []
    enum Call: Equatable {
        case create
        case status
    }

    func createVault() async throws -> VaultStatusResponse {
        calls.append(.create)
        return try createResult.get()
    }

    func status() async throws -> VaultStatusResponse {
        calls.append(.status)
        return try statusResult.get()
    }

    // HER-105 — browser surface; defaults are inert. Tests that exercise
    // the browser configure these per-instance.
    var listFilesResult: Result<VaultFileListResponse, Error> = .success(
        VaultFileListResponse(files: [], limit: 0, nextBefore: nil)
    )
    var readFileResult: Result<(Data, String), Error> = .success((Data(), "text/plain"))
    var moveFileResult: Result<VaultFileDTO, Error> = .success(
        VaultFileDTO(id: UUID(), path: "moved.md", contentType: "text/markdown", sizeBytes: 0, sha256: "")
    )
    var deleteFileResult: Result<Void, Error> = .success(())

    func listFiles(
        spaceSlug _: String?,
        q _: String?,
        before _: Date?,
        after _: Date?,
        limit _: Int?,
    ) async throws -> VaultFileListResponse {
        try listFilesResult.get()
    }

    func readFile(relativePath _: String) async throws -> (Data, String) {
        try readFileResult.get()
    }

    func moveFile(from _: String, to _: String) async throws -> VaultFileDTO {
        try moveFileResult.get()
    }

    func deleteFile(relativePath _: String) async throws {
        _ = try deleteFileResult.get()
    }

    // HER-212 — scripted vault export bytes.
    var exportVaultResult: Result<(Data, String), Error> = .success((Data("fake-tar".utf8), "application/gzip"))
    func exportVault() async throws -> (Data, String) {
        try exportVaultResult.get()
    }
}
