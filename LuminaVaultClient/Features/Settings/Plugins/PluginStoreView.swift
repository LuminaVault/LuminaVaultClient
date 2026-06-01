// LuminaVaultClient/LuminaVaultClient/Features/Settings/Plugins/PluginStoreView.swift
//
// HER-43 (Slice 1) — Settings → Plugins. Browse the first-party catalog and
// drill into a plugin to install, configure, sync, and uninstall.

import LuminaVaultShared
import SwiftUI

struct PluginStoreView: View {
    @State private var viewModel: PluginStoreViewModel
    let client: any PluginsClientProtocol

    init(client: any PluginsClientProtocol) {
        self.client = client
        _viewModel = State(initialValue: PluginStoreViewModel(client: client))
    }

    var body: some View {
        List {
            switch viewModel.state {
            case .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case let .loaded(catalog, installsBySlug, hermesSkills):
                if catalog.isEmpty {
                    Section { Text("No plugins available yet.").foregroundStyle(.secondary) }
                } else {
                    Section {
                        ForEach(catalog) { entry in
                            NavigationLink {
                                PluginDetailView(
                                    entry: entry,
                                    install: installsBySlug[entry.slug],
                                    client: client,
                                    onChange: { await viewModel.refresh() },
                                )
                            } label: {
                                row(for: entry, install: installsBySlug[entry.slug])
                            }
                        }
                    } footer: {
                        Text("Plugins extend what Lumina can pull in. Connectors stage items into your Imported inbox, where Smart Import files and compiles them.")
                    }
                }

                if !hermesSkills.isEmpty {
                    Section {
                        ForEach(hermesSkills) { entry in
                            hermesRow(for: entry)
                        }
                    } header: {
                        Text("In your Hermes")
                    } footer: {
                        Text("Skills already installed in your Hermes agent. Manage these from Hermes for now; installing from the Hub here is coming soon.")
                    }
                }
            case let .error(message):
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Plugins")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
    private func row(for entry: PluginCatalogEntryDTO, install: PluginInstallDTO?) -> some View {
        HStack {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.body)
                    if entry.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                Text(entry.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if let install {
                Text(install.status == .enabled ? "Installed" : "Disabled")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(install.status == .enabled ? .green : .secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Read-only row for a skill installed in the tenant's Hermes agent.
    @ViewBuilder
    private func hermesRow(for entry: PluginCatalogEntryDTO) -> some View {
        HStack {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.body)
                Text(entry.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
