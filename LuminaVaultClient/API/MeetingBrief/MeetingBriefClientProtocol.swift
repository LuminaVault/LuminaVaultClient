// LuminaVaultClient/LuminaVaultClient/API/MeetingBrief/MeetingBriefClientProtocol.swift

import Foundation
import LuminaVaultShared

protocol MeetingBriefClientProtocol: Sendable {
    /// GET /v1/calendar/events/{id}/brief. An event the caller does not
    /// have (unknown, or another tenant's) is a 404:
    /// `APIError.httpError(statusCode: 404, …)`.
    func brief(eventID: UUID) async throws -> MeetingBriefResponse
}
