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
        case loaded(catalog: [PluginCatalogEntryDTO], installsBySlug: [String: PluginInstallDTO])
        case error(message: String)
    }

    var state: State = .loading

    private let client: any PluginsClientProtocol

    init(client: any PluginsClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            async let catalogTask = client.catalog(category: nil)
            async let installsTask = client.installs()
            let (catalog, installs) = try await (catalogTask, installsTask)
            let bySlug = Dictionary(installs.items.map { ($0.pluginSlug, $0) }, uniquingKeysWith: { first, _ in first })
            state = .loaded(catalog: catalog.items, installsBySlug: bySlug)
        } catch {
            state = .error(message: Self.errorMessage(error))
        }
    }

    func refresh() async { await load() }

    private static func errorMessage(_ error: any Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
