// LuminaVaultClient/LuminaVaultClient/API/Plugins/PluginsClientProtocol.swift
//
// HER-43 (Slice 1) — declarative plugin foundation client. Catalog is
// first-party + static on the server; installs are per-tenant. Install config
// (e.g. a connector API token) is sealed server-side and never echoed back —
// `PluginInstallDTO.hasConfig` reports only whether a config exists.

import Foundation
import LuminaVaultShared

protocol PluginsClientProtocol: Sendable {
    func catalog(category: PluginCategory?) async throws -> PluginCatalogListResponse
    /// HER-43 Slice 3a — read-only skills installed in the tenant's Hermes agent.
    func hermesSkills() async throws -> PluginCatalogListResponse
    func installs() async throws -> PluginInstallsListResponse
    func install(_ body: InstallPluginRequest) async throws -> PluginInstallDTO
    func update(_ id: UUID, _ body: UpdatePluginInstallRequest) async throws -> PluginInstallDTO
    func uninstall(_ id: UUID) async throws
    func sync(_ id: UUID) async throws -> PluginSyncResponse
}
