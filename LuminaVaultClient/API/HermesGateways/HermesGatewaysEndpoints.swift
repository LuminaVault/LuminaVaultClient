// LuminaVaultClient/LuminaVaultClient/API/HermesGateways/HermesGatewaysEndpoints.swift
//
// HER-241 — server contract:
//   GET    /v1/me/hermes-gateways                  -> HermesGatewaysListResponse
//   GET    /v1/me/hermes-gateways/{id}             -> HermesGatewayCatalogEntry
//   PUT    /v1/me/hermes-gateways/{id}             -> HermesGatewayCatalogEntry
//   DELETE /v1/me/hermes-gateways/{id}             -> 204
//   POST   /v1/me/hermes-gateways/{id}/test        -> HermesGatewayTestResponse (200, always)

import Foundation
import LuminaVaultShared

enum HermesGatewaysEndpoints {
    struct List: Endpoint {
        typealias Response = HermesGatewaysListResponse
        var path: String { "/v1/me/hermes-gateways" }
        var method: HTTPMethod { .get }
    }

    struct Get: Endpoint {
        typealias Response = HermesGatewayCatalogEntry
        let id: HermesGatewayID
        var path: String { "/v1/me/hermes-gateways/\(id.rawValue)" }
        var method: HTTPMethod { .get }
    }

    struct Put: Endpoint {
        typealias Response = HermesGatewayCatalogEntry
        let id: HermesGatewayID
        let request: HermesGatewayPutRequest
        var path: String { "/v1/me/hermes-gateways/\(id.rawValue)" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }

    struct Delete: Endpoint {
        typealias Response = EmptyResponse
        let id: HermesGatewayID
        var path: String { "/v1/me/hermes-gateways/\(id.rawValue)" }
        var method: HTTPMethod { .delete }
    }

    struct Test: Endpoint {
        typealias Response = HermesGatewayTestResponse
        let id: HermesGatewayID
        var path: String { "/v1/me/hermes-gateways/\(id.rawValue)/test" }
        var method: HTTPMethod { .post }
    }

    // Actuation — apply all configured gateways to the running container:
    //   POST /v1/me/hermes-gateways/apply              -> StartHermesGatewayApplyResponse
    //   GET  /v1/me/hermes-gateways/apply/{jobID}      -> HermesGatewayApplyJobStatus (poll)
    //   GET  /v1/me/hermes-gateways/apply/{jobID}/stream  (SSE HermesGatewayApplyEvent)

    struct Apply: Endpoint {
        typealias Response = StartHermesGatewayApplyResponse
        var path: String { "/v1/me/hermes-gateways/apply" }
        var method: HTTPMethod { .post }
    }

    struct ApplyStatus: Endpoint {
        typealias Response = HermesGatewayApplyJobStatus
        let jobID: UUID
        var path: String { "/v1/me/hermes-gateways/apply/\(jobID.uuidString.lowercased())" }
        var method: HTTPMethod { .get }
    }

    struct ApplyStream: StreamingEndpoint {
        typealias Event = HermesGatewayApplyEvent
        let jobID: UUID
        var path: String { "/v1/me/hermes-gateways/apply/\(jobID.uuidString.lowercased())/stream" }
        var method: HTTPMethod { .get }
        // A container restart takes tens of seconds; keep the SSE generous.
        var streamTimeout: TimeInterval { 180 }
    }

    // WhatsApp QR pairing — the one gateway with no enterable credential. The
    // server runs `hermes whatsapp` in the tenant container and streams the
    // terminal QR + pairing status:
    //   POST   /v1/me/hermes-gateways/whatsapp/pair                   -> StartWhatsAppPairResponse
    //   GET    /v1/me/hermes-gateways/whatsapp/pair/{sessionID}/stream  (SSE HermesWhatsAppPairEvent)
    //   DELETE /v1/me/hermes-gateways/whatsapp/session                -> HermesGatewayCatalogEntry

    struct StartWhatsAppPair: Endpoint {
        typealias Response = StartWhatsAppPairResponse
        var path: String { "/v1/me/hermes-gateways/whatsapp/pair" }
        var method: HTTPMethod { .post }
    }

    struct WhatsAppPairStream: StreamingEndpoint {
        typealias Event = HermesWhatsAppPairEvent
        let sessionID: UUID
        var path: String { "/v1/me/hermes-gateways/whatsapp/pair/\(sessionID.uuidString.lowercased())/stream" }
        var method: HTTPMethod { .get }
        // Pairing can sit on a QR for a while before the user scans; Hermes
        // refreshes the code roughly every 20s. Give it a wide window.
        var streamTimeout: TimeInterval { 300 }
    }

    struct DeleteWhatsAppSession: Endpoint {
        typealias Response = HermesGatewayCatalogEntry
        var path: String { "/v1/me/hermes-gateways/whatsapp/session" }
        var method: HTTPMethod { .delete }
    }
}
