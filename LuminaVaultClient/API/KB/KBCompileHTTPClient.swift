// LuminaVaultClient/LuminaVaultClient/API/KB/KBCompileHTTPClient.swift
import Foundation
import LuminaVaultShared

final class KBCompileHTTPClient: KBCompileClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func compile(_ request: KBCompileRequest) async throws -> KBCompileResponse {
        try await client.execute(KBCompileEndpoints.Compile(request: request))
    }
}
