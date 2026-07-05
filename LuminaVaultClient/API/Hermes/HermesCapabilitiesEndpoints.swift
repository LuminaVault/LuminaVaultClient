// LuminaVaultClient/LuminaVaultClient/API/Hermes/HermesCapabilitiesEndpoints.swift
//
// P3 — server contract:
//   GET /v1/me/hermes/capabilities[?refresh=true] -> HermesCapabilitiesResponse
//
// Managed tenants report every domain as `.managed`; BYO-Hermes tenants get a
// cached probe of their remote api_server so panes can gate on live /
// read_only / unsupported.

import Foundation
import LuminaVaultShared

enum HermesCapabilitiesEndpoints {
    struct Get: Endpoint {
        typealias Response = HermesCapabilitiesResponse
        var refresh: Bool = false
        var path: String { refresh ? "/v1/me/hermes/capabilities?refresh=true" : "/v1/me/hermes/capabilities" }
        var method: HTTPMethod { .get }
    }
}
