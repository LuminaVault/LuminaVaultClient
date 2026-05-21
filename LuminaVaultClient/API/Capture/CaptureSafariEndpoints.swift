// LuminaVaultClient/LuminaVaultClient/API/Capture/CaptureSafariEndpoints.swift
//
// HER-257 — endpoint wrapper for the URL capture surface.
//   POST /v1/capture/safari -> CaptureSafariResponse  (HER-149)
//
// The wire DTOs are defined here as client-local types because
// LuminaVaultShared does not yet vend them; a follow-up shared bump
// will hoist them and replace these definitions verbatim.

import Foundation

/// Wire request — matches openapi.yaml `CaptureSafariRequest`.
struct CaptureSafariRequest: Codable, Sendable {
    let url: String
    let notes: String?
    let spaceId: UUID?
    init(url: String, notes: String? = nil, spaceId: UUID? = nil) {
        self.url = url; self.notes = notes; self.spaceId = spaceId
    }
}

/// Wire response — matches openapi.yaml `CaptureSafariResponse`.
struct CaptureSafariResponse: Codable, Sendable {
    enum EnrichmentStatus: String, Codable, Sendable {
        case pending, complete, failed
    }
    let vaultFileId: UUID
    let enrichmentStatus: EnrichmentStatus?
}

enum CaptureSafariEndpoints {
    struct Capture: Endpoint {
        typealias Response = CaptureSafariResponse
        let request: CaptureSafariRequest

        var path: String { "/v1/capture/safari" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
        var encoder: JSONEncoder {
            let e = JSONEncoder()
            e.keyEncodingStrategy = .convertToSnakeCase
            return e
        }
    }
}
