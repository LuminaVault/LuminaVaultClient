// LuminaVaultClient/LuminaVaultClient/API/Plugins/PluginsHTTPClient.swift
//
// HER-43 (Slice 1) — concrete `PluginsClientProtocol` backed by
// `BaseHTTPClient`.

import Foundation
import LuminaVaultShared

final class PluginsHTTPClient: PluginsClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func catalog(category: PluginCategory?) async throws -> PluginCatalogListResponse {
        try await client.execute(PluginsEndpoints.Catalog(category: category))
    }

    func hermesSkills() async throws -> PluginCatalogListResponse {
        try await client.execute(PluginsEndpoints.HermesSkills())
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
}
