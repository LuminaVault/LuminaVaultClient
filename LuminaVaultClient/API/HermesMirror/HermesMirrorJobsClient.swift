// LuminaVaultClient/LuminaVaultClient/API/HermesMirror/HermesMirrorJobsClient.swift
//
// Hermes Companion Phase 2 — BaseHTTPClient-backed mirror job control.

import Foundation
import LuminaVaultShared

protocol HermesMirrorJobsClientProtocol: Sendable {
    func jobs() async throws -> HermesMirroredJobsResponse
    func create(_ request: HermesJobCreateRequest) async throws -> HermesMirroredJobDTO
    func update(_ jobID: String, _ request: HermesJobUpdateRequest) async throws -> HermesMirroredJobDTO
    func pause(_ jobID: String) async throws -> HermesMirroredJobDTO
    func resume(_ jobID: String) async throws -> HermesMirroredJobDTO
    func trigger(_ jobID: String) async throws -> HermesMirroredJobDTO
    func delete(_ jobID: String) async throws
    func runs(_ jobID: String, limit: Int?) async throws -> HermesJobRunsResponse
    func collect(_ jobID: String) async throws -> HermesJobCollectResultDTO
}

final class HermesMirrorJobsHTTPClient: HermesMirrorJobsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func jobs() async throws -> HermesMirroredJobsResponse {
        try await client.execute(HermesMirrorJobsEndpoints.List())
    }

    func create(_ request: HermesJobCreateRequest) async throws -> HermesMirroredJobDTO {
        try await client.execute(HermesMirrorJobsEndpoints.Create(request: request))
    }

    func update(_ jobID: String, _ request: HermesJobUpdateRequest) async throws -> HermesMirroredJobDTO {
        try await client.execute(HermesMirrorJobsEndpoints.Update(jobID: jobID, request: request))
    }

    func pause(_ jobID: String) async throws -> HermesMirroredJobDTO {
        try await client.execute(HermesMirrorJobsEndpoints.Control(jobID: jobID, action: .pause))
    }

    func resume(_ jobID: String) async throws -> HermesMirroredJobDTO {
        try await client.execute(HermesMirrorJobsEndpoints.Control(jobID: jobID, action: .resume))
    }

    func trigger(_ jobID: String) async throws -> HermesMirroredJobDTO {
        try await client.execute(HermesMirrorJobsEndpoints.Control(jobID: jobID, action: .trigger))
    }

    func delete(_ jobID: String) async throws {
        _ = try await client.execute(HermesMirrorJobsEndpoints.Delete(jobID: jobID))
    }

    func runs(_ jobID: String, limit: Int? = 50) async throws -> HermesJobRunsResponse {
        try await client.execute(HermesMirrorJobsEndpoints.Runs(jobID: jobID, limit: limit))
    }

    func collect(_ jobID: String) async throws -> HermesJobCollectResultDTO {
        try await client.execute(HermesMirrorJobsEndpoints.Collect(jobID: jobID))
    }
}

/// Phase 2's stable error codes. Same envelope shape as Phase 1's — the code
/// arrives as `error.message` — but a different vocabulary, and one case
/// worth separating from the rest: `hermes_mirror_not_configured` means the
/// user has no Hermes linked at all, which is a setup step, not a fault.
enum HermesMirrorFailure: Equatable, Sendable {
    /// 409 — no Hermes linked to this account yet.
    case notConfigured
    /// 501 — the linked Hermes is too old for this operation.
    case unsupported
    /// 404 — no such job on that Hermes.
    case notFound
    /// 502 — Hermes was reachable but errored, or its dashboard rejected us.
    case upstream
    /// 502 — the BYO dashboard refused the credentials we hold.
    case dashboardUnauthorized
    case badRequest
    case unauthorized
    case offline
    case unknown(String)

    init(_ error: any Error) {
        guard let apiError = error as? APIError else {
            self = .unknown(error.localizedDescription)
            return
        }
        switch apiError {
        case .unauthorized:
            self = .unauthorized
        case .networkFailure, .tlsPinningFailed:
            self = .offline
        case .httpError(let status, let data):
            self = Self.fromHTTP(status: status, data: data)
        default:
            self = .unknown(apiError.userFacingMessage)
        }
    }

    private static func fromHTTP(status: Int, data: Data) -> HermesMirrorFailure {
        switch Self.stableCode(in: data) {
        case "hermes_mirror_not_configured": return .notConfigured
        case "hermes_mirror_unsupported": return .unsupported
        case "hermes_mirror_not_found": return .notFound
        case "hermes_dashboard_unauthorized": return .dashboardUnauthorized
        case "hermes_dashboard_auth_mode_unsupported": return .unsupported
        // These two are 400s. Without naming them the `hermes_mirror_` prefix
        // below would swallow them as upstream failures and offer a retry
        // that cannot work.
        case "hermes_mirror_invalid_path", "hermes_mirror_body_too_large": return .badRequest
        case let code? where code.hasPrefix("hermes_mirror_") || code.hasPrefix("hermes_dashboard_"):
            return .upstream
        default: break
        }
        switch status {
        case 400: return .badRequest
        case 401: return .unauthorized
        case 404: return .notFound
        case 409: return .notConfigured
        case 501: return .unsupported
        case 502, 503, 504: return .upstream
        default: return .unknown("Server error (\(status)).")
        }
    }

    private static func stableCode(in data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return nil
        }
        return message
    }

    var message: String {
        switch self {
        case .notConfigured: return "No Hermes is linked to this account yet."
        case .unsupported: return "Your Hermes is too old for this."
        case .notFound: return "That job no longer exists on your Hermes."
        case .upstream: return "Your Hermes couldn't be reached."
        case .dashboardUnauthorized: return "Your Hermes dashboard rejected the saved credentials."
        case .badRequest: return "Hermes didn't accept that schedule."
        case .unauthorized: return "Session expired — sign in again."
        case .offline: return "You're offline."
        case .unknown(let text): return text
        }
    }

    var guidance: String? {
        switch self {
        case .notConfigured: return "Link one in Settings → Hermes Gateway."
        case .unsupported: return "Update Hermes and try again."
        case .dashboardUnauthorized: return "Re-enter the dashboard token in Settings → Hermes Gateway."
        case .upstream: return "Check that your Hermes is online."
        case .offline: return "Reconnect and try again."
        default: return nil
        }
    }

    var isRetryable: Bool {
        switch self {
        case .notConfigured, .unsupported, .notFound, .badRequest:
            return false
        case .upstream, .dashboardUnauthorized, .unauthorized, .offline, .unknown:
            return true
        }
    }
}
