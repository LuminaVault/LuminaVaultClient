// Protocol seam so the Brain graph store can stub the network in tests.

import Foundation
import LuminaVaultShared

protocol BrainGraphClientProtocol: Sendable {
    /// GET /v1/brain/graph
    func fetchGraph(_ request: BrainGraphRequest) async throws -> BrainGraphResponse
}
