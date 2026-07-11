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
                let visible = filtered(catalog)
                let marketplace = filteredMarketplace(viewModel.marketplace)

                if !marketplace.isEmpty {
                    Section("Marketplace") {
                        ForEach(marketplace) { plugin in
                            NavigationLink {
                                MarketplacePluginDetailView(
                                    plugin: plugin,
                                    install: installsBySlug[plugin.slug],
                                    client: client,
                                    onChange: { await viewModel.refresh() }
                                )
                            } label: {
                                marketplaceRow(plugin, install: installsBySlug[plugin.slug])
                            }
                        }
                    }
                }

                if !viewModel.featured.isEmpty, viewModel.searchText.isEmpty {
                    Section("Featured") {
                        ForEach(viewModel.featured) { entry in
                            catalogLink(entry, installsBySlug)
                        }
                    }
                }

                if visible.isEmpty, marketplace.isEmpty {
                    Section {
                        Text(viewModel.searchText.isEmpty
                            ? "No plugins available yet."
                            : "No plugins match “\(viewModel.searchText)”.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Self.categoryOrder, id: \.self) { category in
                        let inCategory = visible.filter { $0.category == category }
                        if !inCategory.isEmpty {
                            Section(Self.categoryTitle(category)) {
                                ForEach(inCategory) { entry in
                                    catalogLink(entry, installsBySlug)
                                }
                            }
                        }
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
        .searchable(
            text: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
            prompt: "Search plugins"
        )
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Catalog rows + grouping (Slice 6)

    private static let categoryOrder: [PluginCategory] = [.connector, .capture, .skill, .memory, .export, .ui, .theme]

    private static func categoryTitle(_ category: PluginCategory) -> String {
        switch category {
        case .connector: "Connectors"
        case .capture: "Capture"
        case .skill: "Skills"
        case .memory: "Memory"
        case .export: "Export"
        case .ui: "Interface"
        case .theme: "Themes"
        }
    }

    private func filtered(_ entries: [PluginCatalogEntryDTO]) -> [PluginCatalogEntryDTO] {
        let q = viewModel.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.name.lowercased().contains(q) || $0.summary.lowercased().contains(q) }
    }

    private func filteredMarketplace(_ entries: [MarketplacePluginDTO]) -> [MarketplacePluginDTO] {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedStandardContains(query) || $0.summary.localizedStandardContains(query) }
    }

    private func marketplaceRow(_ plugin: MarketplacePluginDTO, install: PluginInstallDTO?) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: plugin.iconURL.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "shippingbox.fill").foregroundStyle(.tint)
            }
            .frame(width: 36, height: 36)
            .clipShape(.rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(plugin.name)
                    if plugin.publisher.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                            .accessibilityLabel("Verified publisher")
                    }
                }
                Text(plugin.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Label(
                    plugin.ratingCount == 0 ? "No ratings" : "\(plugin.ratingAverage.formatted(.number.precision(.fractionLength(1)))) from \(plugin.ratingCount)",
                    systemImage: "star.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if install != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Installed")
            }
        }
        .padding(.vertical, 3)
    }

    private func catalogLink(_ entry: PluginCatalogEntryDTO, _ installsBySlug: [String: PluginInstallDTO]) -> some View {
        NavigationLink {
            PluginDetailView(
                entry: entry,
                install: installsBySlug[entry.slug],
                client: client,
                onChange: { await viewModel.refresh() }
            )
        } label: {
            row(for: entry, install: installsBySlug[entry.slug])
        }
    }

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
                    if viewModel.premiumSlugs.contains(entry.slug) {
                        Text("PRO")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.25), in: Capsule())
                            .foregroundStyle(.orange)
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
            set: { viewModel.hubInstallText = $0 }
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
