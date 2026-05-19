// LuminaVaultClient/LuminaVaultClient/API/KB/KBCompileHTTPClient.swift
import Foundation
import LuminaVaultShared

final class KBCompileHTTPClient: KBCompileClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func compile(_ request: KBCompileRequest) async throws -> KBCompileResponse {
        try await compile(request, idempotencyKey: nil)
    }

    // HER-39 — sync-engine entrypoint. Carries an `Idempotency-Key` so the
    // server replays the cached response on retry.
    func compile(_ request: KBCompileRequest, idempotencyKey: UUID?) async throws -> KBCompileResponse {
        try await client.execute(KBCompileEndpoints.Compile(request: request, idempotencyKey: idempotencyKey))
    }
}
