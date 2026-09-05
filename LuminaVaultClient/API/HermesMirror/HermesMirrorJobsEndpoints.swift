// LuminaVaultClient/LuminaVaultClient/API/HermesMirror/HermesMirrorJobsEndpoints.swift
//
// Hermes Companion Phase 2 "Collect" — `/v1/hermes/mirror/jobs`. Full
// control of the cron jobs on the tenant's own Hermes, plus the run history
// LuminaVault has collected from them.
//
// The runs route is the reason Phase 2 exists on the phone at all: it reads
// stored rows, never the tenant's Hermes, so it answers while that machine
// is asleep. Everything else here goes through to Hermes and fails when it
// is offline.

import Foundation
import LuminaVaultShared

enum HermesMirrorJobsEndpoints {
    struct List: Endpoint {
        typealias Response = HermesMirroredJobsResponse
        var path: String { "/v1/hermes/mirror/jobs" }
        var method: HTTPMethod { .get }
    }

    struct Create: Endpoint {
        typealias Response = HermesMirroredJobDTO
        let request: HermesJobCreateRequest
        var path: String { "/v1/hermes/mirror/jobs" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    struct Update: Endpoint {
        typealias Response = HermesMirroredJobDTO
        let jobID: String
        let request: HermesJobUpdateRequest
        var path: String { "/v1/hermes/mirror/jobs/\(HermesMirrorJobsEndpoints.escape(jobID))" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }

    /// `pause`, `resume` and `trigger` share a shape: no body, the updated
    /// job back.
    struct Control: Endpoint {
        enum Action: String {
            case pause, resume, trigger
        }

        typealias Response = HermesMirroredJobDTO
        let jobID: String
        let action: Action
        var path: String {
            "/v1/hermes/mirror/jobs/\(HermesMirrorJobsEndpoints.escape(jobID))/\(action.rawValue)"
        }

        var method: HTTPMethod { .post }
    }

    struct Delete: Endpoint {
        typealias Response = EmptyResponse
        let jobID: String
        var path: String { "/v1/hermes/mirror/jobs/\(HermesMirrorJobsEndpoints.escape(jobID))" }
        var method: HTTPMethod { .delete }
    }

    /// `GET /v1/hermes/mirror/jobs/{id}/runs?limit=` — newest first. The
    /// server clamps `limit` to 1...200 and defaults to 50.
    struct Runs: Endpoint {
        typealias Response = HermesJobRunsResponse
        let jobID: String
        let limit: Int?
        var path: String {
            let base = "/v1/hermes/mirror/jobs/\(HermesMirrorJobsEndpoints.escape(jobID))/runs"
            guard let limit else { return base }
            return "\(base)?limit=\(limit)"
        }

        var method: HTTPMethod { .get }
    }

    /// Pulls this job's finished runs now rather than waiting for the
    /// collector tick. Idempotent — already-collected runs are skipped by
    /// run key.
    struct Collect: Endpoint {
        typealias Response = HermesJobCollectResultDTO
        let jobID: String
        var path: String { "/v1/hermes/mirror/jobs/\(HermesMirrorJobsEndpoints.escape(jobID))/collect" }
        var method: HTTPMethod { .post }
    }

    /// Hermes job ids are free-form strings, not UUIDs, so they cannot be
    /// interpolated into a path unescaped.
    static func escape(_ jobID: String) -> String {
        jobID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobID
    }
}
