// LuminaVaultClient/LuminaVaultClient/API/Integrations/IntegrationsModels.swift
//
// HER-240b — wire DTOs for `/v1/integrations/xai`. Mirrors the server-local
// DTO definitions on the LuminaVaultServer side (HER-240a). Both will move
// to `LuminaVaultShared` once that package's version graph settles; until
// then the iOS shapes are local to keep the two repos shippable
// independently (see HER-213 precedent).

import Foundation
import LuminaVaultShared

/// GET /v1/integrations/xai — current state of the tenant's xAI Grok OAuth
/// connection. `tier` mirrors the server User row's tier column
/// (`trial` | `pro` | `ultimate` | `lapsed` | `archived`).
struct XaiStatusResponse: Codable, Sendable, Equatable {
    let connected: Bool
    let tier: String
    let xaiConnectedAt: Date?
}

/// POST /v1/integrations/xai/start — server returns the upstream authorize
/// URL the client opens in a `WKWebView`. `sessionID` is opaque and echoed
/// back on `complete`. Server-side TTL: 10 minutes.
struct XaiStartResponse: Codable, Sendable, Equatable {
    let sessionID: String
    let authorizeURL: String
}

/// POST /v1/integrations/xai/complete — client posts the captured
/// loopback callback URL (host `127.0.0.1`, port `56121`, path
/// `/callback`, query `?code=…&state=…`).
struct XaiCompleteRequest: Codable, Sendable, Equatable {
    let sessionID: String
    let callbackURL: String
}

// MARK: - Nous Portal subscription (OAuth device-code)
//
// Wire DTOs now live in LuminaVaultShared (single source of truth, per
// CLAUDE.md §3). Aliased here so call sites keep the short names.

typealias NousStatusResponse = LuminaVaultShared.NousStatusResponse
typealias NousStartResponse = LuminaVaultShared.NousStartResponse
typealias NousCompleteRequest = LuminaVaultShared.NousCompleteRequest
