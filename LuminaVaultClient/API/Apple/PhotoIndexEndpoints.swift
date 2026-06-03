// LuminaVaultClient/LuminaVaultClient/API/Apple/PhotoIndexEndpoints.swift
//
// Apple Photos derived-text index — POST /v1/photos/index.
//
// PRIVACY-CRITICAL: the body carries only derived text (OCR), on-device scene
// tags, and metadata — never pixel data.
//
// Encoding: camelCase keys + ISO8601 dates. The server's request decoder does
// NOT apply `convertFromSnakeCase` (it decodes the shared DTO field names
// verbatim, e.g. `assetLocalID`), so we must NOT snake-case the keys here —
// matching the `/v1/apple/consent` path rather than the health-ingest path.

import Foundation
import LuminaVaultShared

extension JSONEncoder {
    /// Photos ingest encoder — camelCase keys (server decodes DTO names
    /// verbatim) + ISO8601 dates (matches `takenAt` server-side).
    static let lvPhotos: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    /// Photos ingest decoder — `AppleSyncResponse` is plain Ints, but the
    /// shared response decoder convention keeps ISO8601 dates available.
    static let lvPhotos: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

enum PhotoIndexEndpoints {
    /// `POST /v1/photos/index` — batch ingest derived OCR text + scene tags +
    /// metadata. Consent-gated server-side on the `photos` domain.
    struct Index: Endpoint {
        typealias Response = AppleSyncResponse
        let items: [PhotoIndexInput]

        var path: String { "/v1/photos/index" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { true }
        var body: (any Encodable)? { PhotoIndexSyncRequest(items: items) }
        var encoder: JSONEncoder { .lvPhotos }
        var decoder: JSONDecoder { .lvPhotos }
    }
}
