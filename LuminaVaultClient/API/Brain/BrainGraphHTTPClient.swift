// BaseHTTPClient-backed implementation of BrainGraphClientProtocol.

import Foundation
import LuminaVaultShared

final class BrainGraphHTTPClient: BrainGraphClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func fetchGraph(_ request: BrainGraphRequest) async throws -> BrainGraphResponse {
        try await client.execute(BrainGraphEndpoints.Graph(request: request))
    }
}
