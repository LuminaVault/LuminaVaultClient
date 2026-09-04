// LuminaVaultClient/LuminaVaultClient/API/Hermes/HermesRunsEndpoints.swift
//
// Hermes Companion Phase 1 — `/v1/hermes/runs`. Start an agent run on the
// tenant's own Hermes, list and read runs, follow one live over SSE, answer
// its approval prompts and stop it.
//
// Wire format notes:
//   - Every DTO comes from `LuminaVaultShared` (see CLAUDE.md §3). The
//     server encodes with Hummingbird's default JSON coder, which is
//     camelCase keys + ISO-8601 dates — exactly what `JSONDecoder.hvDefault`
//     reads, so no per-endpoint decoder is needed.
//   - The events feed is a `StreamingEndpoint`, so it rides the shared
//     `BaseHTTPClient` byte-level SSE parser rather than a second frame
//     parser of its own.

import Foundation
import LuminaVaultShared

enum HermesRunsEndpoints {
    /// `POST /v1/hermes/runs` — 202 with the persisted run.
    struct Start: Endpoint {
        typealias Response = HermesRunDTO
        let request: HermesRunStartRequest
        var path: String { "/v1/hermes/runs" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    /// `GET /v1/hermes/runs?limit=` — newest first, server-capped at 50.
    struct List: Endpoint {
        typealias Response = HermesRunListResponse
        let limit: Int?
        var path: String {
            guard let limit else { return "/v1/hermes/runs" }
            return "/v1/hermes/runs?limit=\(limit)"
        }

        var method: HTTPMethod { .get }
    }

    /// `GET /v1/hermes/runs/{id}` — includes `pendingApproval`.
    struct Get: Endpoint {
        typealias Response = HermesRunDTO
        let runID: UUID
        var path: String { "/v1/hermes/runs/\(runID.uuidString)" }
        var method: HTTPMethod { .get }
    }

    /// `POST /v1/hermes/runs/{id}/approval`.
    struct Approve: Endpoint {
        typealias Response = HermesRunDTO
        let runID: UUID
        let request: HermesRunApprovalRequest
        var path: String { "/v1/hermes/runs/\(runID.uuidString)/approval" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    /// `POST /v1/hermes/runs/{id}/stop`. Hermes answers `stopping`, so the
    /// returned DTO may still read `running` — the terminal state lands on
    /// the event feed.
    struct Stop: Endpoint {
        typealias Response = HermesRunDTO
        let runID: UUID
        var path: String { "/v1/hermes/runs/\(runID.uuidString)/stop" }
        var method: HTTPMethod { .post }
    }

    /// `GET /v1/hermes/runs/{id}/events?after=<seq>` — SSE, replay then live.
    ///
    /// `after` is the highest `seq` the client already holds (`lastSeq` on
    /// the run, or the last event it rendered). Passing it means a
    /// backgrounded app that reconnects resumes where it stopped instead of
    /// replaying the whole run, and never sees an event twice.
    struct Events: StreamingEndpoint {
        typealias Event = HermesRunEventDTO
        let runID: UUID
        let after: Int

        var path: String {
            let base = "/v1/hermes/runs/\(runID.uuidString)/events"
            guard after > 0 else { return base }
            return "\(base)?after=\(after)"
        }

        var method: HTTPMethod { .get }
        /// A run can sit on an approval prompt for a long time before the
        /// next event arrives. The server's own backstop tick is 5 s, so
        /// silence longer than the 120 s default only ever means a dead
        /// connection — but a paused agent should not race it.
        var streamTimeout: TimeInterval { 600 }
    }
}
