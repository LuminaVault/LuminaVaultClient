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

    /// Recorded so a test can assert *what* was asked for — the Space filter
    /// and the keyset cursor are the two arguments whose loss is silent.
    struct ListFilesCall: Equatable {
        let spaceSlug: String?
        let q: String?
        let before: Date?
        let after: Date?
        let limit: Int?
    }
    private(set) var listFilesCalls: [ListFilesCall] = []

    func listFiles(
        spaceSlug: String?,
        q: String?,
        before: Date?,
        after: Date?,
        limit: Int?,
    ) async throws -> VaultFileListResponse {
        listFilesCalls.append(
            ListFilesCall(spaceSlug: spaceSlug, q: q, before: before, after: after, limit: limit)
        )
        return try listFilesResult.get()
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
