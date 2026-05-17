// LuminaVaultClient/LuminaVaultClient/API/Memo/MemoHTTPClient.swift
// HER-37: BaseHTTPClient-backed implementation of MemoClientProtocol.
import Foundation

final class MemoHTTPClient: MemoClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func generate(_ request: MemoRequest) async throws -> MemoResponse {
        try await client.execute(MemoEndpoints.Generate(request: request))
    }

    func list() async throws -> MemoListResponse {
        try await client.execute(MemoEndpoints.List())
    }
}
