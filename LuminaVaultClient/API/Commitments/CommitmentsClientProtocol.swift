// LuminaVaultClient/LuminaVaultClient/API/Commitments/CommitmentsClientProtocol.swift

import Foundation
import LuminaVaultShared

protocol CommitmentsClientProtocol: Sendable {
    /// GET /v1/me/commitments?state=
    func commitments(state: CommitmentsQueryState) async throws -> CommitmentsResponse

    /// PATCH /v1/me/commitments/{id} {state}. Reopening one that would
    /// duplicate an open commitment throws `APIError.httpError(409, …)`.
    func update(id: UUID, state: CommitmentState) async throws -> CommitmentDTO
}
