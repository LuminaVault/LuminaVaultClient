// LuminaVaultClient/LuminaVaultClient/Features/Settings/Plugins/PluginStoreViewModel.swift
//
// HER-43 (Slice 1) — Plugin Store list state. Loads the first-party catalog
// and this tenant's installs together, merging by slug so each row shows
// whether it's installed.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class PluginStoreViewModel {
    enum State: Equatable {
        case loading
        case loaded(
            catalog: [PluginCatalogEntryDTO],
            installsBySlug: [String: PluginInstallDTO],
            hermesSkills: [PluginCatalogEntryDTO]
        )
        case error(message: String)
    }

    var state: State = .loading

    // HER-43 Slice 6 — marketplace curation + search.
    var featured: [PluginCatalogEntryDTO] = []
    var premiumSlugs: Set<String> = []
    var searchText: String = ""
    var marketplace: [MarketplacePluginDTO] = []

    // HER-43 Slice 5 — Hermes Hub install field + in-flight/error feedback.
    var hubInstallText: String = ""
    var hubBusy: Bool = false
    var hubError: String?

    private let client: any PluginsClientProtocol

    init(client: any PluginsClientProtocol) {
        self.client = client
    }

    private enum Loaded: Sendable {
        case catalog(PluginCatalogListResponse)
        case installs(PluginInstallsListResponse)
        case hermes(PluginCatalogListResponse?)
        case featured(PluginCatalogListResponse?)
        case premium(PluginCatalogListResponse?)
        case marketplace(MarketplaceListResponse?)
    }

    func load() async {
        state = .loading
        do {
            var loadedCatalog: PluginCatalogListResponse?
            var loadedInstalls: PluginInstallsListResponse?
            var hermes: PluginCatalogListResponse?
            var featured: PluginCatalogListResponse?
            var premium: PluginCatalogListResponse?
            var marketplace: MarketplaceListResponse?
            // A task group, not `async let`: see HomeGlanceViewModel.load().
            try await withThrowingTaskGroup(of: Loaded.self) { group in
                group.addTask { .catalog(try await self.client.catalog(category: nil)) }
                group.addTask { .installs(try await self.client.installs()) }
                // Best-effort: Hermes may be unreachable; show an empty section
                // rather than failing the whole store.
                group.addTask { .hermes(try? await self.client.hermesSkills()) }
                // Curation (best-effort): empty/unbadged if these fail.
                group.addTask { .featured(try? await self.client.featuredPlugins()) }
                group.addTask { .premium(try? await self.client.premiumPlugins()) }
                group.addTask {
                    .marketplace(try? await self.client.marketplace(query: nil, category: nil))
                }
                for try await item in group {
                    switch item {
                    case .catalog(let value): loadedCatalog = value
                    case .installs(let value): loadedInstalls = value
                    case .hermes(let value): hermes = value
                    case .featured(let value): featured = value
                    case .premium(let value): premium = value
                    case .marketplace(let value): marketplace = value
                    }
                }
            }
            guard let catalog = loadedCatalog, let installs = loadedInstalls else { return }
            let bySlug = Dictionary(installs.items.map { ($0.pluginSlug, $0) }, uniquingKeysWith: { first, _ in first })
            self.featured = featured?.items ?? []
            premiumSlugs = Set((premium?.items ?? []).map(\.slug))
            self.marketplace = marketplace?.items ?? []
            state = .loaded(
                catalog: catalog.items,
                installsBySlug: bySlug,
                hermesSkills: hermes?.items ?? []
            )
        } catch {
            state = .error(message: Self.errorMessage(error))
        }
    }

    func refresh() async {
        await load()
    }

    // MARK: - Hermes Hub install/uninstall (Slice 5)

    func installHubSkill() async {
        let id = hubInstallText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !hubBusy else { return }
        hubBusy = true
        hubError = nil
        defer { hubBusy = false }
        do {
            let resp = try await client.installHermesSkill(id: id)
            hubInstallText = ""
            applyHermesSkills(resp.items)
        } catch {
            hubError = Self.errorMessage(error)
        }
    }

    func uninstallHubSkill(name: String) async {
        guard !hubBusy else { return }
        hubBusy = true
        hubError = nil
        defer { hubBusy = false }
        do {
            let resp = try await client.uninstallHermesSkill(name: name)
            applyHermesSkills(resp.items)
        } catch {
            hubError = Self.errorMessage(error)
        }
    }

    /// Replace just the Hermes-skills section after an install/uninstall (the
    /// endpoints return the refreshed list), leaving catalog + installs intact.
    private func applyHermesSkills(_ items: [PluginCatalogEntryDTO]) {
        guard case let .loaded(catalog, installsBySlug, _) = state else { return }
        state = .loaded(catalog: catalog, installsBySlug: installsBySlug, hermesSkills: items)
    }

    private static func errorMessage(_ error: any Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
