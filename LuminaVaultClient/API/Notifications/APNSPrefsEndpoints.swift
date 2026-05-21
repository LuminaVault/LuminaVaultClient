// LuminaVaultClient/LuminaVaultClient/API/Notifications/APNSPrefsEndpoints.swift
//
// HER-179 — GET/PUT /v1/me/apns-categories.

import Foundation
import LuminaVaultShared

enum APNSPrefsEndpoints {
    struct Get: Endpoint {
        typealias Response = APNSCategoryPrefsResponse
        var path: String { "/v1/me/apns-categories" }
        var method: HTTPMethod { .get }
    }

    struct Put: Endpoint {
        typealias Response = APNSCategoryPrefsResponse
        let request: APNSCategoryPrefsPutRequest
        var path: String { "/v1/me/apns-categories" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }
}
