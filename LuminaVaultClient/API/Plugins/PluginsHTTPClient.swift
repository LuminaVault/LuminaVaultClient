// LuminaVaultClient/LuminaVaultClient/API/Plugins/PluginsHTTPClient.swift
//
// HER-43 (Slice 1) — concrete `PluginsClientProtocol` backed by
// `BaseHTTPClient`.

import Foundation
import LuminaVaultShared

final class PluginsHTTPClient: PluginsClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func catalog(category: PluginCategory?) async throws -> PluginCatalogListResponse {
        try await client.execute(PluginsEndpoints.Catalog(category: category))
    }

    func featuredPlugins() async throws -> PluginCatalogListResponse {
        try await client.execute(PluginsEndpoints.Catalog(featured: true))
    }

    func premiumPlugins() async throws -> PluginCatalogListResponse {
        try await client.execute(PluginsEndpoints.Catalog(premium: true))
    }

    func hermesSkills() async throws -> PluginCatalogListResponse {
        try await client.execute(PluginsEndpoints.HermesSkills())
    }

    func installHermesSkill(id: String) async throws -> PluginCatalogListResponse {
        try await client.execute(PluginsEndpoints.HermesSkillInstall(id: id))
    }

    func uninstallHermesSkill(name: String) async throws -> PluginCatalogListResponse {
        try await client.execute(PluginsEndpoints.HermesSkillUninstall(name: name))
    }

    func installs() async throws -> PluginInstallsListResponse {
        try await client.execute(PluginsEndpoints.Installs())
    }

    func install(_ body: InstallPluginRequest) async throws -> PluginInstallDTO {
        try await client.execute(PluginsEndpoints.Install(request: body))
    }

    func update(_ id: UUID, _ body: UpdatePluginInstallRequest) async throws -> PluginInstallDTO {
        try await client.execute(PluginsEndpoints.Update(id: id, request: body))
    }

    func uninstall(_ id: UUID) async throws {
        _ = try await client.execute(PluginsEndpoints.Delete(id: id))
    }

    func sync(_ id: UUID) async throws -> PluginSyncResponse {
        try await client.execute(PluginsEndpoints.Sync(id: id))
    }

    func marketplace(query: String?, category: PluginCategory?) async throws -> MarketplaceListResponse {
        try await client.execute(PluginsEndpoints.Marketplace(query: query, category: category))
    }

    func marketplaceDetail(slug: String) async throws -> MarketplacePluginDTO {
        try await client.execute(PluginsEndpoints.MarketplaceDetail(slug: slug))
    }

    func marketplaceReviews(slug: String) async throws -> MarketplaceReviewsResponse {
        try await client.execute(PluginsEndpoints.MarketplaceReviews(slug: slug))
    }

    func installMarketplace(slug: String, request: MarketplaceInstallRequest) async throws -> PluginInstallDTO {
        try await client.execute(PluginsEndpoints.MarketplaceInstall(slug: slug, request: request))
    }

    func rateMarketplace(slug: String, request: MarketplaceRatingRequest) async throws -> MarketplaceReviewDTO {
        try await client.execute(PluginsEndpoints.MarketplaceRating(slug: slug, request: request))
    }
}
