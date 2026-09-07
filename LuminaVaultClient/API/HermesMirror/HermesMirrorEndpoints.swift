// LuminaVaultClient/LuminaVaultClient/API/HermesMirror/HermesMirrorEndpoints.swift
//
// Mirror status and sync. iOS previously knew only the job routes, so a user
// could link a Hermes and had no way to see whether anything had been
// imported — or to ask for a sync. The gateway pane showed a green
// "Connected" badge next to no numbers at all.

import Foundation
import LuminaVaultShared

enum HermesMirrorEndpoints {
    /// `GET /v1/hermes/mirror/status` — counts, last sync, vault state.
    struct Status: Endpoint {
        typealias Response = HermesMirrorStatusDTO
        var path: String { "/v1/hermes/mirror/status" }
        var method: HTTPMethod { .get }
        /// A passive load on the settings screen. A 402 here must surface in
        /// the card, not slide the app-root paywall over the user.
        var presentsPaywallOn402: Bool { false }
    }

    /// `POST /v1/hermes/mirror/sync` — pull skills, jobs and vault state.
    ///
    /// Returns the same status shape, so the card can render the result
    /// without a second round trip.
    struct Sync: Endpoint {
        typealias Response = HermesMirrorStatusDTO
        let scope: [HermesMirrorSyncScope]?
        var path: String { "/v1/hermes/mirror/sync" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { HermesMirrorSyncRequest(scope: scope) }
        var presentsPaywallOn402: Bool { false }
    }
}
