// LuminaVaultClient/LuminaVaultClient/API/Commitments/CommitmentsEndpoints.swift
//
// Commitments ("open loops") — first-person promises kb-compile pulled out
// of the user's own notes.
//
// GET /v1/me/commitments?state=open|done|dropped|all — default `open`; open
// ones come due first, closed ones most recently closed first.
//
// PATCH /v1/me/commitments/{id} {state} → the updated `CommitmentDTO`. `done`
// and `dropped` stamp `doneAt`; `open` clears it, and is a 409 when another
// open commitment already says the same thing.

import Foundation
import LuminaVaultShared

/// The `state` query of the list endpoint. Not a wire DTO — the server takes
/// the same three states `CommitmentState` carries, plus `all`.
nonisolated enum CommitmentsQueryState: String, Sendable, CaseIterable {
    case open
    case done
    case dropped
    case all
}

nonisolated enum CommitmentsEndpoints {
    nonisolated struct List: Endpoint {
        typealias Response = CommitmentsResponse
        let state: CommitmentsQueryState

        var path: String {
            "/v1/me/commitments?state=\(state.rawValue)"
        }

        var method: HTTPMethod {
            .get
        }

        /// The brief reads this passively behind its Open loops card.
        var presentsPaywallOn402: Bool {
            false
        }
    }

    nonisolated struct Update: Endpoint {
        typealias Response = CommitmentDTO
        let id: UUID
        let state: CommitmentState

        var path: String {
            "/v1/me/commitments/\(id.uuidString.lowercased())"
        }

        var method: HTTPMethod {
            .patch
        }

        var body: (any Encodable)? {
            CommitmentUpdateRequest(state: state)
        }

        var presentsPaywallOn402: Bool {
            false
        }
    }
}
