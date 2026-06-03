// LuminaVaultClient/LuminaVaultClient/API/Auth/PairingEndpoints.swift
//
// HER — QR-from-mobile web sign-in (app side). The browser shows a QR encoding
// `luminavault://pair?id=<pairingId>&code=<code>`; the authenticated app scans
// it, confirms the code, and approves via this endpoint. The server then hands
// the minted token pair to the polling browser.
import Foundation

enum PairingEndpoints {
    /// Approve a browser pairing. JWT-authenticated: the app vouches for the
    /// browser. Returns 204 on success.
    struct Approve: Endpoint {
        typealias Response = EmptyResponse
        let pairingId: String
        let code: String
        var path: String { "/v1/auth/pairing/\(pairingId)/approve" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { true }
        var body: (any Encodable)? { PairingApproveRequest(code: code) }
    }
}

struct PairingApproveRequest: Encodable {
    let code: String
}
