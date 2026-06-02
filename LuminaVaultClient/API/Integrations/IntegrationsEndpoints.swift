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

    // MARK: - Nous Portal subscription

    struct GetNousStatus: Endpoint {
        typealias Response = NousStatusResponse
        var path: String { "/v1/integrations/nous" }
        var method: HTTPMethod { .get }
    }

    struct StartNousConnect: Endpoint {
        typealias Response = NousStartResponse
        var path: String { "/v1/integrations/nous/start" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { nil }
    }

    struct CompleteNousConnect: Endpoint {
        typealias Response = NousStatusResponse
        let sessionID: String
        var path: String { "/v1/integrations/nous/complete" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? {
            NousCompleteRequest(sessionID: sessionID)
        }
    }

    struct DisconnectNous: Endpoint {
        typealias Response = NousStatusResponse
        var path: String { "/v1/integrations/nous" }
        var method: HTTPMethod { .delete }
    }
}
