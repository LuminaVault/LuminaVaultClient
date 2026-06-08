// LuminaVaultClient/LuminaVaultClient/API/Import/VaultImportClient.swift

import Foundation

protocol VaultImportClientProtocol: Sendable {
    func bulk(space: String, files: [VaultBulkFile]) async throws -> VaultBulkResponse
}

struct VaultImportHTTPClient: VaultImportClientProtocol {
    let client: BaseHTTPClient

    func bulk(space: String, files: [VaultBulkFile]) async throws -> VaultBulkResponse {
        try await client.execute(
            VaultImportEndpoints.Bulk(request: VaultBulkRequest(space: space, files: files)),
        )
    }
}
