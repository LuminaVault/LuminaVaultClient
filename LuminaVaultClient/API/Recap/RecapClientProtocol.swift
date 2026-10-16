// LuminaVaultClient/LuminaVaultClient/API/Recap/RecapClientProtocol.swift

import Foundation
import LuminaVaultShared

protocol RecapClientProtocol: Sendable {
    /// GET /v1/me/recap — `.week` (7d) or `.month` (30d). The server also
    /// accepts nothing else; `.quarter` is an analytics range, not a recap.
    func recap(range: AnalyticsRange) async throws -> MeRecapResponse
}
