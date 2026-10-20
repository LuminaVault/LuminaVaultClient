// LuminaVaultClient/LuminaVaultClient/API/Brief/BriefClientProtocol.swift

import Foundation
import LuminaVaultShared

protocol BriefClientProtocol: Sendable {
    /// GET /v1/me/brief?date= — `date` nil is today in the user's timezone.
    /// A day without a brief is `MeBriefResponse(brief: nil)`, not an error.
    func brief(date: String?) async throws -> MeBriefResponse

    /// POST /v1/me/brief/{briefId}/cards/{cardId}/feedback → 204.
    func feedback(briefID: UUID, cardID: String, action: BriefCardFeedbackAction) async throws
}
