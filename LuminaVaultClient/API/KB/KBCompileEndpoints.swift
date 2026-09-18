// LuminaVaultClient/LuminaVaultClient/API/KB/KBCompileEndpoints.swift
// HER-36: the endpoints behind "Sync & Learn".
//
// The server renamed these from `/v1/kb-compile` to `/v1/memory-compile`
// (HER-240). The old paths still answer, but only as a 308 redirect the
// server's own OpenAPI marks deprecated and promises to keep for one
// milestone — so pointing at them is a dated cheque. The guided-start card
// reads the pending count to decide whether its Sync & Learn step can
// complete at all, and when that probe eventually 404s the step opens a
// spotlight that can only end in its five-minute timeout. Cheaper to use the
// real names now.
import Foundation
import LuminaVaultShared

enum KBCompileEndpoints {
    struct Compile: Endpoint {
        typealias Response = KBCompileResponse
        let request: KBCompileRequest
        let idempotencyKey: UUID?
        init(request: KBCompileRequest, idempotencyKey: UUID? = nil) {
            self.request = request
            self.idempotencyKey = idempotencyKey
        }
        var path: String { "/v1/memory-compile" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    /// HER-293 — `GET /v1/memory-compile/pending`. Cheap probe: the
    /// "Sync & Learn" surface disables its button when nothing is pending,
    /// and the guided-start card refuses to open step 2 for the same reason.
    /// Polling on focus is fine; it does not touch the compile rate limit.
    struct Pending: Endpoint {
        typealias Response = KBCompilePendingResponse
        var path: String { "/v1/memory-compile/pending" }
        var method: HTTPMethod { .get }
    }
}
