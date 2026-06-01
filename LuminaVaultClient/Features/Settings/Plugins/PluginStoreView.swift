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

                Section {
                    hubInstallField
                    ForEach(hermesSkills) { entry in
                        hermesRow(for: entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await viewModel.uninstallHubSkill(name: Self.hermesName(entry)) }
                                } label: {
                                    Label("Uninstall", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("Hermes Hub")
                } footer: {
                    Text("Install community skills into your Hermes agent by id or URL (from the Hermes Skills Hub). Swipe a skill to uninstall.")
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

    /// "Add from Hermes Hub": paste a skill id/URL and install it into the
    /// tenant's Hermes container.
    @ViewBuilder
    private var hubInstallField: some View {
        let text = Binding(
            get: { viewModel.hubInstallText },
            set: { viewModel.hubInstallText = $0 },
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("skill id or URL", text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(viewModel.hubBusy)
                Button {
                    Task { await viewModel.installHubSkill() }
                } label: {
                    if viewModel.hubBusy {
                        ProgressView()
                    } else {
                        Text("Install")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.hubBusy || viewModel.hubInstallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let hubError = viewModel.hubError {
                Text(hubError).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    /// Recover the Hermes skill name from a `hermes-<name>` catalog slug.
    private static func hermesName(_ entry: PluginCatalogEntryDTO) -> String {
        let prefix = "hermes-"
        return entry.slug.hasPrefix(prefix) ? String(entry.slug.dropFirst(prefix.count)) : entry.slug
    }
}
