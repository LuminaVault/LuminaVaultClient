// GET /v1/brain/graph — one graph of notes and memories across the user's vaults.

import Foundation
import LuminaVaultShared

nonisolated enum BrainGraphEndpoints {
    nonisolated struct Graph: Endpoint {
        typealias Response = BrainGraphResponse

        let request: BrainGraphRequest

        /// `BrainGraphRequest.query` already holds the path and query string;
        /// BaseHTTPClient appends it to its base URL as is.
        var path: String { request.query }

        var method: HTTPMethod { .get }

        // Same as the old graph endpoint: a 402 must not slide the app-root
        // paywall over the Brain tab. The screen renders the failure itself.
        var presentsPaywallOn402: Bool { false }
    }
}
