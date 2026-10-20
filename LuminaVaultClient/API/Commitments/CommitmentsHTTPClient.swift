// LuminaVaultClient/LuminaVaultClient/API/Commitments/CommitmentsHTTPClient.swift
//
// BaseHTTPClient-backed `CommitmentsClientProtocol`. Built by
// `AppState.makeCommitmentsClient()`.

import Foundation
import LuminaVaultShared

final class CommitmentsHTTPClient: CommitmentsClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func commitments(state: CommitmentsQueryState) async throws -> CommitmentsResponse {
        try await client.execute(CommitmentsEndpoints.List(state: state))
    }

    func update(id: UUID, state: CommitmentState) async throws -> CommitmentDTO {
        try await client.execute(CommitmentsEndpoints.Update(id: id, state: state))
    }
}
