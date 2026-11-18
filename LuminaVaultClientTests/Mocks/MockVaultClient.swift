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
        if !listFilesQueue.isEmpty { return listFilesQueue.removeFirst() }
        return try listFilesResult.get()
    }

    /// Answers consumed in order before `listFilesResult`, for flows that
    /// list, change something, and list again.
    var listFilesQueue: [VaultFileListResponse] = []

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

    // Backlog E3.4 — scripted trash.
    var listTrashResult: Result<[VaultTrashItem], Error> = .success([])
    var restoreTrashResult: Result<VaultFileDTO, Error> = .success(
        VaultFileDTO(id: UUID(), path: "restored.md", contentType: "text/markdown", sizeBytes: 0, sha256: "")
    )
    var deleteTrashResult: Result<Void, Error> = .success(())
    private(set) var restoredTrashIDs: [UUID] = []
    private(set) var deletedTrashIDs: [UUID] = []

    func listTrash() async throws -> [VaultTrashItem] {
        try listTrashResult.get()
    }

    func restoreTrash(id: UUID) async throws -> VaultFileDTO {
        restoredTrashIDs.append(id)
        return try restoreTrashResult.get()
    }

    func deleteTrashForever(id: UUID) async throws {
        deletedTrashIDs.append(id)
        try deleteTrashResult.get()
    }

    // Backlog E6.4 — scripted daily notes and templates.
    // Backlog E4.5: history.
    var historyResult: Result<[VaultHistoryVersion], Error> = .success([])
    var readVersionResult: Result<(Data, String), Error> = .success((Data(), "text/markdown"))
    var restoreVersionResult: Result<VaultFileDTO, Error> = .success(
        VaultFileDTO(id: UUID(), path: "inbox/a.md", contentType: "text/markdown", sizeBytes: 0, sha256: "")
    )
    private(set) var historyPaths: [String] = []
    private(set) var restoreVersionCalls: [(sha: String, path: String, ifMatch: String?)] = []

    func history(path: String) async throws -> [VaultHistoryVersion] {
        historyPaths.append(path)
        return try historyResult.get()
    }

    func readVersion(sha _: String, path _: String) async throws -> (Data, String) {
        try readVersionResult.get()
    }

    func restoreVersion(sha: String, path: String, ifMatch: String?) async throws -> VaultFileDTO {
        restoreVersionCalls.append((sha, path, ifMatch))
        return try restoreVersionResult.get()
    }

    var dailyNoteResult: Result<VaultFileDTO, Error> = .success(
        VaultFileDTO(id: UUID(), path: "daily/2026-11-16.md", contentType: "text/markdown", sizeBytes: 0, sha256: "")
    )
    var seedTemplatesResult: Result<VaultTemplatesSeedResponse, Error> = .success(
        VaultTemplatesSeedResponse(spaceId: UUID(), created: [])
    )
    var noteFromTemplateResult: Result<VaultFileDTO, Error> = .success(
        VaultFileDTO(id: UUID(), path: "inbox/note.md", contentType: "text/markdown", sizeBytes: 0, sha256: "")
    )
    private(set) var dailyNoteZones: [String?] = []
    private(set) var seedTemplatesCalls = 0
    private(set) var noteFromTemplateRequests: [VaultFromTemplateRequest] = []

    func dailyNote(tz: String?) async throws -> VaultFileDTO {
        dailyNoteZones.append(tz)
        return try dailyNoteResult.get()
    }

    func seedTemplates() async throws -> VaultTemplatesSeedResponse {
        seedTemplatesCalls += 1
        return try seedTemplatesResult.get()
    }

    func noteFromTemplate(_ request: VaultFromTemplateRequest) async throws -> VaultFileDTO {
        noteFromTemplateRequests.append(request)
        return try noteFromTemplateResult.get()
    }

    // Backlog E8.5: properties and views. A queue of query results, one per call.
    var queryResults: [Result<VaultQueryResponse, Error>] = []
    private(set) var queryRequests: [VaultQueryRequest] = []

    func query(_ request: VaultQueryRequest) async throws -> VaultQueryResponse {
        queryRequests.append(request)
        guard !queryResults.isEmpty else { throw URLError(.unsupportedURL) }
        return try queryResults.removeFirst().get()
    }
}
