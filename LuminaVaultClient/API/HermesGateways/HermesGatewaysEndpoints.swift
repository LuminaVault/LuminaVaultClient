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
}
