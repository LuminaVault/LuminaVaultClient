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
    /// HER-43 Slice 5 — install a Hermes Hub skill by id/URL into the tenant's
    /// container; returns the refreshed installed list.
    func installHermesSkill(id: String) async throws -> PluginCatalogListResponse
    /// HER-43 Slice 5 — uninstall a skill (by Hermes name) from the container;
    /// returns the refreshed installed list.
    func uninstallHermesSkill(name: String) async throws -> PluginCatalogListResponse
    func installs() async throws -> PluginInstallsListResponse
    func install(_ body: InstallPluginRequest) async throws -> PluginInstallDTO
    func update(_ id: UUID, _ body: UpdatePluginInstallRequest) async throws -> PluginInstallDTO
    func uninstall(_ id: UUID) async throws
    func sync(_ id: UUID) async throws -> PluginSyncResponse
}
