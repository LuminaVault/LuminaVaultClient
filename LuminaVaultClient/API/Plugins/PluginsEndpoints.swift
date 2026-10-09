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

nonisolated enum PluginsEndpoints {
    nonisolated struct Catalog: Endpoint {
        typealias Response = PluginCatalogListResponse
        var category: PluginCategory? = nil
        var featured: Bool? = nil
        var premium: Bool? = nil
        var path: String {
            var items: [String] = []
            if let category {
                items.append("category=\(category.rawValue)")
            }
            if let featured {
                items.append("featured=\(featured)")
            }
            if let premium {
                items.append("premium=\(premium)")
            }
            return items.isEmpty ? "/v1/plugins/catalog" : "/v1/plugins/catalog?\(items.joined(separator: "&"))"
        }

        var method: HTTPMethod {
            .get
        }
    }

    nonisolated struct HermesSkills: Endpoint {
        typealias Response = PluginCatalogListResponse
        var path: String {
            "/v1/plugins/hermes-skills"
        }

        var method: HTTPMethod {
            .get
        }
    }

    nonisolated struct HermesSkillInstall: Endpoint {
        typealias Response = PluginCatalogListResponse
        let id: String
        var path: String {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
            return "/v1/plugins/hermes-skills/install?id=\(encoded)"
        }

        var method: HTTPMethod {
            .post
        }
    }

    nonisolated struct HermesSkillUninstall: Endpoint {
        typealias Response = PluginCatalogListResponse
        let name: String
        var path: String {
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            return "/v1/plugins/hermes-skills/\(encoded)"
        }

        var method: HTTPMethod {
            .delete
        }
    }

    nonisolated struct Installs: Endpoint {
        typealias Response = PluginInstallsListResponse
        var path: String {
            "/v1/plugins/installs"
        }

        var method: HTTPMethod {
            .get
        }
    }

    nonisolated struct Install: Endpoint {
        typealias Response = PluginInstallDTO
        let request: InstallPluginRequest
        var path: String {
            "/v1/plugins/installs"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }

    nonisolated struct Update: Endpoint {
        typealias Response = PluginInstallDTO
        let id: UUID
        let request: UpdatePluginInstallRequest
        var path: String {
            "/v1/plugins/installs/\(id.uuidString)"
        }

        var method: HTTPMethod {
            .patch
        }

        var body: (any Encodable)? {
            request
        }
    }

    nonisolated struct Delete: Endpoint {
        typealias Response = EmptyResponse
        let id: UUID
        var path: String {
            "/v1/plugins/installs/\(id.uuidString)"
        }

        var method: HTTPMethod {
            .delete
        }
    }

    nonisolated struct Sync: Endpoint {
        typealias Response = PluginSyncResponse
        let id: UUID
        var path: String {
            "/v1/plugins/installs/\(id.uuidString)/sync"
        }

        var method: HTTPMethod {
            .post
        }
    }

    nonisolated struct Marketplace: Endpoint {
        typealias Response = MarketplaceListResponse
        let query: String?
        let category: PluginCategory?
        var path: String {
            var components = URLComponents()
            components.path = "/v1/marketplace/plugins"
            components.queryItems = [
                query.map { URLQueryItem(name: "query", value: $0) },
                category.map { URLQueryItem(name: "category", value: $0.rawValue) },
            ].compactMap { $0 }
            return components.string ?? components.path
        }

        var method: HTTPMethod {
            .get
        }
    }

    nonisolated struct MarketplaceDetail: Endpoint {
        typealias Response = MarketplacePluginDTO
        let slug: String
        var path: String {
            "/v1/marketplace/plugins/\(slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug)"
        }

        var method: HTTPMethod {
            .get
        }
    }

    nonisolated struct MarketplaceReviews: Endpoint {
        typealias Response = MarketplaceReviewsResponse
        let slug: String
        var path: String {
            "/v1/marketplace/plugins/\(slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug)/reviews"
        }

        var method: HTTPMethod {
            .get
        }
    }

    nonisolated struct MarketplaceInstall: Endpoint {
        typealias Response = PluginInstallDTO
        let slug: String
        let request: MarketplaceInstallRequest
        var path: String {
            "/v1/marketplace/plugins/\(slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug)/install"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }

    nonisolated struct MarketplaceUpgrade: Endpoint {
        typealias Response = PluginInstallDTO
        let slug: String
        let request: MarketplaceUpgradeRequest
        var path: String {
            "/v1/marketplace/plugins/\(slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug)/upgrade"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }

    nonisolated struct MarketplaceRating: Endpoint {
        typealias Response = MarketplaceReviewDTO
        let slug: String
        let request: MarketplaceRatingRequest
        var path: String {
            "/v1/marketplace/plugins/\(slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug)/rating"
        }

        var method: HTTPMethod {
            .put
        }

        var body: (any Encodable)? {
            request
        }
    }
}
