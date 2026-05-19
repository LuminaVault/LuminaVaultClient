// LuminaVaultClient/LuminaVaultClient/API/Integrations/IntegrationsEndpoints.swift
//
// HER-240b — endpoint definitions for `/v1/integrations/xai`.

import Foundation

enum IntegrationsEndpoints {
    struct GetXaiStatus: Endpoint {
        typealias Response = XaiStatusResponse
        var path: String { "/v1/integrations/xai" }
        var method: HTTPMethod { .get }
    }

    struct StartXaiConnect: Endpoint {
        typealias Response = XaiStartResponse
        var path: String { "/v1/integrations/xai/start" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { nil }
    }

    struct CompleteXaiConnect: Endpoint {
        typealias Response = XaiStatusResponse
        let sessionID: String
        let callbackURL: String
        var path: String { "/v1/integrations/xai/complete" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? {
            XaiCompleteRequest(sessionID: sessionID, callbackURL: callbackURL)
        }
    }

    struct DisconnectXai: Endpoint {
        typealias Response = XaiStatusResponse
        var path: String { "/v1/integrations/xai" }
        var method: HTTPMethod { .delete }
    }
}
