// LuminaVaultClient/LuminaVaultClient/API/Notifications/DeviceEndpoints.swift
//
// HER-214 — APNS device-token registration endpoints.
//   POST   /v1/devices         -> DeviceRegistrationResponse
//   DELETE /v1/devices/{token} -> 204 No Content

import Foundation
import LuminaVaultShared

enum DeviceEndpoints {
    struct Register: Endpoint {
        typealias Response = DeviceRegistrationResponse
        let request: DeviceRegistrationRequest
        var path: String { "/v1/devices" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    struct Unregister: Endpoint {
        typealias Response = EmptyResponse
        let token: String
        var path: String {
            let escaped = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
            return "/v1/devices/\(escaped)"
        }
        var method: HTTPMethod { .delete }
    }
}
