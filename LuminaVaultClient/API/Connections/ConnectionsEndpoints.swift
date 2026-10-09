// LuminaVaultClient/LuminaVaultClient/API/Connections/ConnectionsEndpoints.swift
//
// Backend contract:
//   GET  /v1/me/connections
//   POST /v1/me/connections/test-all
//   GET  /v1/me/connections/events
import Foundation

nonisolated enum ConnectionsEndpoints {
    nonisolated struct Summary: Endpoint {
        typealias Response = ConnectionsSummaryResponse

        var path: String { "/v1/me/connections" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct TestAll: Endpoint {
        typealias Response = ConnectionsTestAllResponse

        var path: String { "/v1/me/connections/test-all" }
        var method: HTTPMethod { .post }
    }

    nonisolated struct Events: Endpoint {
        typealias Response = ConnectionDiagnosticEventsResponse
        let limit: Int

        var path: String { "/v1/me/connections/events?limit=\(limit)" }
        var method: HTTPMethod { .get }
    }
}
