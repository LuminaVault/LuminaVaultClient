// LuminaVaultClient/LuminaVaultClient/API/KB/KBCompileEndpoints.swift
// HER-36: POST /v1/kb-compile — drives the "Sync & Learn" tab.
import Foundation
import LuminaVaultShared

enum KBCompileEndpoints {
    struct Compile: Endpoint {
        typealias Response = KBCompileResponse
        let request: KBCompileRequest
        var path: String { "/v1/kb-compile" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }
}
