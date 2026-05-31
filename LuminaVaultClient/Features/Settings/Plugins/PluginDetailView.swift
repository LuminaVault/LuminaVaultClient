// LuminaVaultClient/LuminaVaultClient/Features/Settings/Plugins/PluginDetailView.swift
//
// HER-43 (Slice 1) — per-plugin detail screen. Renders the catalog entry's
// config fields (text / secret / url), installs/updates config, enables or
// disables, runs a connector sync, and uninstalls.

import LuminaVaultShared
import SwiftUI

struct PluginDetailView: View {
    @State private var viewModel: PluginDetailViewModel
    @State private var showUninstallConfirm = false

    init(
        entry: PluginCatalogEntryDTO,
        install: PluginInstallDTO?,
        client: any PluginsClientProtocol,
        onChange: @escaping () async -> Void,
    ) {
        _viewModel = State(initialValue: PluginDetailViewModel(
            entry: entry, install: install, client: client, onChange: onChange,
        ))
    }

    var body: some View {
        Form {
            Section {
                Text(viewModel.entry.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            configSection

            actionSection

            if viewModel.isInstalled {
                manageSection
            }

            outcomeSection
        }
        .navigationTitle(viewModel.entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    @ViewBuilder
    private var configSection: some View {
        if !viewModel.entry.configFields.isEmpty {
            Section {
                ForEach(viewModel.entry.configFields, id: \.key) { field in
                    fieldEditor(field)
                }
            } header: {
                Text("Configuration")
            } footer: {
                if viewModel.isInstalled {
                    Text("Already configured. Re-enter values to rotate the stored config — secrets are never shown back.")
                }
            }
        }
    }

    @ViewBuilder
    private func fieldEditor(_ field: PluginConfigField) -> some View {
        let binding = Binding(
            get: { viewModel.values[field.key] ?? "" },
            set: { viewModel.values[field.key] = $0 },
        )
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label).font(.caption).foregroundStyle(.secondary)
            switch field.kind {
            case .secret:
                SecureField(field.placeholder ?? "", text: binding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .url:
                TextField(field.placeholder ?? "https://…", text: binding)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .text:
                TextField(field.placeholder ?? "", text: binding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            Button(viewModel.isInstalled ? "Save config" : "Install") {
                Task { await viewModel.installOrUpdate() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.outcome == .working)
        }
    }

    @ViewBuilder
    private var manageSection: some View {
        Section("Manage") {
            Toggle("Enabled", isOn: Binding(
                get: { viewModel.isEnabled },
                set: { newValue in Task { await viewModel.setEnabled(newValue) } },
            ))

            if viewModel.entry.capabilityKind == .connector {
                Button("Sync now") {
                    Task { await viewModel.sync() }
                }
                .disabled(!viewModel.isEnabled || viewModel.outcome == .working)
            }

            if let lastSync = viewModel.install?.lastSyncAt {
                LabeledContent("Last sync", value: lastSync.formatted(date: .abbreviated, time: .shortened))
            }

            Button("Uninstall", role: .destructive) { showUninstallConfirm = true }
                .disabled(viewModel.outcome == .working)
        }
        .confirmationDialog(
            "Uninstall \(viewModel.entry.name)?",
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible,
        ) {
            Button("Uninstall", role: .destructive) {
                Task { await viewModel.uninstall() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the stored config. Items already imported into your vault stay.")
        }
    }

    @ViewBuilder
    private var outcomeSection: some View {
        switch viewModel.outcome {
        case .idle, .working:
            EmptyView()
        case .installed:
            Section {
                Label("Config saved.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        case let .synced(staged, skipped):
            Section {
                Label("Synced — \(staged) staged, \(skipped) skipped. Open Imported to review.", systemImage: "tray.and.arrow.down.fill")
                    .foregroundStyle(.green)
            }
        case let .error(message):
            Section { Text(message).foregroundStyle(.red) }
        }
    }
}
