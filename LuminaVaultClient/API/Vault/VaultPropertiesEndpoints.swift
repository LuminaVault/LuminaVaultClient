// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultPropertiesEndpoints.swift
// Backlog E8.5: the read-only properties and views routes. Every one answers
// 404 while the server's VAULT_PROPERTIES_ENABLED is off.
import Foundation

nonisolated extension VaultEndpoints {
    struct PropertyTypes: Endpoint {
        typealias Response = VaultPropertyTypesResponse
        var path: String {
            "/v1/vault/property-types"
        }

        var method: HTTPMethod {
            .get
        }

        var presentsPaywallOn402: Bool {
            false
        }
    }

    /// The file list again, decoded for `properties` only. `q` is a substring
    /// match, so the caller picks the exact path out of the results.
    struct FileProperties: Endpoint {
        typealias Response = VaultFilePropertiesListResponse
        let filePath: String
        var path: String {
            VaultEndpoints.withQuery("/v1/vault/files", [
                URLQueryItem(name: "q", value: filePath),
                URLQueryItem(name: "limit", value: "50"),
            ])
        }

        var method: HTTPMethod {
            .get
        }

        var presentsPaywallOn402: Bool {
            false
        }
    }

    struct Views: Endpoint {
        typealias Response = VaultViewsResponse
        var path: String {
            "/v1/vault/views"
        }

        var method: HTTPMethod {
            .get
        }

        var presentsPaywallOn402: Bool {
            false
        }
    }

    struct Query: Endpoint {
        typealias Response = VaultQueryResponse
        let request: VaultQueryRequest
        var path: String {
            "/v1/vault/query"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }

        var presentsPaywallOn402: Bool {
            false
        }
    }
}
