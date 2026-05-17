// LuminaVaultClient/LuminaVaultClient/API/Account/AccountEndpoints.swift
// HER-212: DELETE /v1/account.
import Foundation

enum AccountEndpoints {
    struct Delete: Endpoint {
        typealias Response = EmptyResponse
        var path: String { "/v1/account" }
        var method: HTTPMethod { .delete }
    }
}
