// LuminaVaultClient/LuminaVaultClient/API/System/SystemHermesEndpoints.swift
//
// HER-330 — owner-only "Update Hermes" endpoints under /v1/system/hermes.
// Every request carries the `X-Admin-Token` header (in addition to the
// session JWT) because an update affects the whole server. The token is read
// from the Keychain at request-build time.

import Foundation
import LuminaVaultShared

enum SystemHermesEndpoints {
    /// Builds the `X-Admin-Token` header dict from the stored secret, or empty
    /// when none is set (server then returns 401 → UI prompts for it).
    private static func adminHeaders() -> [String: String] {
        guard let token = KeychainService.shared.hermesAdminToken, !token.isEmpty else { return [:] }
        return ["X-Admin-Token": token]
    }

    /// Thin wire envelopes. The meaningful DTOs live in `LuminaVaultShared`;
    /// these single-field wrappers mirror the server's response shape.
    struct VersionResponse: Decodable { let info: HermesVersionInfo }
    struct JobStatusResponse: Decodable { let status: HermesUpdateJobStatus }

    struct Version: Endpoint {
        typealias Response = VersionResponse
        var path: String { "/v1/system/hermes/version" }
        var method: HTTPMethod { .get }
        var additionalHeaders: [String: String] { adminHeaders() }
    }

    struct Start: Endpoint {
        typealias Response = StartHermesUpdateResponse
        let request: StartHermesUpdateRequest
        var path: String { "/v1/system/hermes/update" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
        var additionalHeaders: [String: String] { adminHeaders() }
    }

    struct Current: Endpoint {
        typealias Response = JobStatusResponse
        var path: String { "/v1/system/hermes/update/current" }
        var method: HTTPMethod { .get }
        var additionalHeaders: [String: String] { adminHeaders() }
    }

    struct Status: Endpoint {
        typealias Response = JobStatusResponse
        let jobID: UUID
        var path: String { "/v1/system/hermes/update/\(jobID.uuidString.lowercased())" }
        var method: HTTPMethod { .get }
        var additionalHeaders: [String: String] { adminHeaders() }
    }

    struct Rollback: Endpoint {
        typealias Response = StartHermesUpdateResponse
        let jobID: UUID
        var path: String { "/v1/system/hermes/update/\(jobID.uuidString.lowercased())/rollback" }
        var method: HTTPMethod { .post }
        var additionalHeaders: [String: String] { adminHeaders() }
    }

    struct Stream: StreamingEndpoint {
        typealias Event = HermesUpdateEvent
        let jobID: UUID
        var path: String { "/v1/system/hermes/update/\(jobID.uuidString.lowercased())/stream" }
        var method: HTTPMethod { .get }
        // An update can take minutes; keep the SSE connection generous.
        var streamTimeout: TimeInterval { 600 }
        var additionalHeaders: [String: String] { adminHeaders() }
    }
}
