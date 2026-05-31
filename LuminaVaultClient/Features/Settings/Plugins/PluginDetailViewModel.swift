// LuminaVaultClient/LuminaVaultClient/Features/Settings/Plugins/PluginDetailViewModel.swift
//
// HER-43 (Slice 1) — per-plugin detail/install state. Renders the catalog
// entry's config fields, installs/updates config (secrets always start blank —
// the server never echoes them back), enables/disables, runs a connector sync,
// and uninstalls. `onChange` lets the store refresh its install badges.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class PluginDetailViewModel {
    enum Outcome: Equatable, Sendable {
        case idle
        case working
        case installed
        case synced(staged: Int, skipped: Int)
        case error(message: String)
    }

    let entry: PluginCatalogEntryDTO
    var install: PluginInstallDTO?
    /// Form values keyed by config-field key. Seeded blank.
    var values: [String: String]
    var outcome: Outcome = .idle

    private let client: any PluginsClientProtocol
    private let onChange: () async -> Void

    init(
        entry: PluginCatalogEntryDTO,
        install: PluginInstallDTO?,
        client: any PluginsClientProtocol,
        onChange: @escaping () async -> Void,
    ) {
        self.entry = entry
        self.install = install
        self.client = client
        self.onChange = onChange
        values = Dictionary(uniqueKeysWithValues: entry.configFields.map { ($0.key, "") })
    }

    var isInstalled: Bool { install != nil }
    var isEnabled: Bool { install?.status == .enabled }

    // MARK: - Actions

    func installOrUpdate() async {
        for field in entry.configFields where field.isRequired {
            let value = values[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty {
                outcome = .error(message: "Missing \(field.label).")
                return
            }
        }
        outcome = .working
        do {
            let dto: PluginInstallDTO
            if let install {
                dto = try await client.update(install.id, UpdatePluginInstallRequest(config: values, status: nil))
            } else {
                dto = try await client.install(InstallPluginRequest(pluginSlug: entry.slug, config: values))
            }
            install = dto
            outcome = .installed
            await onChange()
        } catch {
            outcome = .error(message: Self.errorMessage(error))
        }
    }

    func sync() async {
        guard let install else { return }
        outcome = .working
        do {
            let result = try await client.sync(install.id)
            outcome = .synced(staged: result.staged, skipped: result.skipped)
            await onChange()
        } catch {
            outcome = .error(message: Self.errorMessage(error))
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard let install else { return }
        do {
            let dto = try await client.update(
                install.id,
                UpdatePluginInstallRequest(config: nil, status: enabled ? .enabled : .disabled),
            )
            self.install = dto
            await onChange()
        } catch {
            outcome = .error(message: Self.errorMessage(error))
        }
    }

    func uninstall() async {
        guard let install else { return }
        outcome = .working
        do {
            try await client.uninstall(install.id)
            self.install = nil
            values = Dictionary(uniqueKeysWithValues: entry.configFields.map { ($0.key, "") })
            outcome = .idle
            await onChange()
        } catch {
            outcome = .error(message: Self.errorMessage(error))
        }
    }

    private static func errorMessage(_ error: any Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
