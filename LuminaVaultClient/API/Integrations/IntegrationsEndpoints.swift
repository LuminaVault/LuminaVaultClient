// LuminaVaultClient/LuminaVaultClient/API/Integrations/IntegrationsEndpoints.swift
//
// HER-240b — endpoint definitions for `/v1/integrations/xai`.

import Foundation

nonisolated enum IntegrationsEndpoints {
    nonisolated struct GetXaiStatus: Endpoint {
        typealias Response = XaiStatusResponse
        var path: String { "/v1/integrations/xai" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct StartXaiConnect: Endpoint {
        typealias Response = XaiStartResponse
        var path: String { "/v1/integrations/xai/start" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { nil }
    }

    nonisolated struct CompleteXaiConnect: Endpoint {
        typealias Response = XaiStatusResponse
        let sessionID: String
        let callbackURL: String
        var path: String { "/v1/integrations/xai/complete" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? {
            XaiCompleteRequest(sessionID: sessionID, callbackURL: callbackURL)
        }
    }

    nonisolated struct DisconnectXai: Endpoint {
        typealias Response = XaiStatusResponse
        var path: String { "/v1/integrations/xai" }
        var method: HTTPMethod { .delete }
    }

    // MARK: - Nous Portal subscription

    nonisolated struct GetNousStatus: Endpoint {
        typealias Response = NousStatusResponse
        var path: String { "/v1/integrations/nous" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct StartNousConnect: Endpoint {
        typealias Response = NousStartResponse
        var path: String { "/v1/integrations/nous/start" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { nil }
    }

    nonisolated struct CompleteNousConnect: Endpoint {
        typealias Response = NousStatusResponse
        let sessionID: String
        var path: String { "/v1/integrations/nous/complete" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? {
            NousCompleteRequest(sessionID: sessionID)
        }
    }

    nonisolated struct DisconnectNous: Endpoint {
        typealias Response = NousStatusResponse
        var path: String { "/v1/integrations/nous" }
        var method: HTTPMethod { .delete }
    }
}
