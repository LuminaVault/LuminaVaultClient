// LuminaVaultClient/LuminaVaultClient/API/Plugins/PluginsEndpoints.swift
//
// HER-43 (Slice 1) — server contract:
//   GET    /v1/plugins/catalog[?category=]        -> PluginCatalogListResponse
//   GET    /v1/plugins/installs                   -> PluginInstallsListResponse
//   POST   /v1/plugins/installs                   -> PluginInstallDTO
//   PATCH  /v1/plugins/installs/{id}              -> PluginInstallDTO
//   DELETE /v1/plugins/installs/{id}              -> 204
//   POST   /v1/plugins/installs/{id}/sync         -> PluginSyncResponse

import Foundation
import LuminaVaultShared

enum PluginsEndpoints {
    struct Catalog: Endpoint {
        typealias Response = PluginCatalogListResponse
        let category: PluginCategory?
        var path: String {
            guard let category else { return "/v1/plugins/catalog" }
            return "/v1/plugins/catalog?category=\(category.rawValue)"
        }
        var method: HTTPMethod { .get }
    }

    struct HermesSkills: Endpoint {
        typealias Response = PluginCatalogListResponse
        var path: String { "/v1/plugins/hermes-skills" }
        var method: HTTPMethod { .get }
    }

    struct HermesSkillInstall: Endpoint {
        typealias Response = PluginCatalogListResponse
        let id: String
        var path: String {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
            return "/v1/plugins/hermes-skills/install?id=\(encoded)"
        }
        var method: HTTPMethod { .post }
    }

    struct HermesSkillUninstall: Endpoint {
        typealias Response = PluginCatalogListResponse
        let name: String
        var path: String {
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            return "/v1/plugins/hermes-skills/\(encoded)"
        }
        var method: HTTPMethod { .delete }
    }

    struct Installs: Endpoint {
        typealias Response = PluginInstallsListResponse
        var path: String { "/v1/plugins/installs" }
        var method: HTTPMethod { .get }
    }

    struct Install: Endpoint {
        typealias Response = PluginInstallDTO
        let request: InstallPluginRequest
        var path: String { "/v1/plugins/installs" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    struct Update: Endpoint {
        typealias Response = PluginInstallDTO
        let id: UUID
        let request: UpdatePluginInstallRequest
        var path: String { "/v1/plugins/installs/\(id.uuidString)" }
        var method: HTTPMethod { .patch }
        var body: (any Encodable)? { request }
    }

    struct Delete: Endpoint {
        typealias Response = EmptyResponse
        let id: UUID
        var path: String { "/v1/plugins/installs/\(id.uuidString)" }
        var method: HTTPMethod { .delete }
    }

    struct Sync: Endpoint {
        typealias Response = PluginSyncResponse
        let id: UUID
        var path: String { "/v1/plugins/installs/\(id.uuidString)/sync" }
        var method: HTTPMethod { .post }
    }
}
