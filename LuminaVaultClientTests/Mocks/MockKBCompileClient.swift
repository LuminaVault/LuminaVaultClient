// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockKBCompileClient.swift
// HER-244 — scripted KBCompileClientProtocol fake used by HomeViewModelTests
// to verify the dashboard's "Trigger Compile" big-button delegates to the
// existing kb-compile flow.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

final class MockKBCompileClient: KBCompileClientProtocol, @unchecked Sendable {
    var compileResult: Result<KBCompileResponse, Error> = .success(
        KBCompileResponse(memoriesIngested: 0, memoriesUpdated: 0, durationMs: 0, runId: UUID())
    )
    var pendingResult: Result<KBCompilePendingResponse, Error> = .success(
        KBCompilePendingResponse(pendingFiles: 0)
    )
    private(set) var compileCallCount: Int = 0
    private(set) var pendingCallCount: Int = 0
    private(set) var lastRequest: KBCompileRequest?

    func compile(_ request: KBCompileRequest) async throws -> KBCompileResponse {
        compileCallCount += 1
        lastRequest = request
        return try compileResult.get()
    }

    func pending() async throws -> KBCompilePendingResponse {
        pendingCallCount += 1
        return try pendingResult.get()
    }
}
