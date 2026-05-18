// LuminaVaultClient/LuminaVaultClient/API/Memo/MemoEndpoints.swift
// HER-37: POST /v1/memos + GET /v1/memos. Wire DTOs come from
// LuminaVaultShared so server + client stay in lockstep.
import Foundation

enum MemoEndpoints {
    struct Generate: Endpoint {
        typealias Response = MemoResponse
        let request: MemoRequest
        var path: String { "/v1/memos" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    struct List: Endpoint {
        typealias Response = MemoListResponse
        var path: String { "/v1/memos" }
        var method: HTTPMethod { .get }
    }
}
