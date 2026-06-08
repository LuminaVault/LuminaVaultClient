// LuminaVaultClient/LuminaVaultClient/Features/Settings/VaultImport/VaultImportView.swift
//
// Settings → Connections → Import Vault. Pick an Obsidian/Hermes vault folder,
// choose which top folders to import (each → a Space), and bulk-ingest markdown
// so chat grounding + the Brain graph use it.

import SwiftUI
import UniformTypeIdentifiers

struct VaultImportView: View {
    @State private var viewModel: VaultImportViewModel
    @State private var picking = false

    init(client: VaultImportClientProtocol) {
        _viewModel = State(initialValue: VaultImportViewModel(client: client))
    }

    var body: some View {
        Form {
            switch viewModel.phase {
            case .idle:
                chooseSection
            case let .failed(message):
                chooseSection
                Section {
                    Text(message).foregroundStyle(.red).font(.footnote)
                }
            case .scanning:
                Section {
                    HStack(spacing: 12) { ProgressView(); Text("Scanning folder…") }
                }
            case .manifest:
                manifestSection
                Section {
                    Button("Import \(selectedCount) notes") {
                        Task { await viewModel.runImport() }
                    }
                    .disabled(!viewModel.canImport)
                }
            case .importing:
                Section {
                    ProgressView(value: viewModel.progress)
                    Text("Importing… \(Int(viewModel.progress * 100))%")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            case .done:
                Section {
                    Label(viewModel.resultText, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } footer: {
                    Text("Open the Brain tab to see your graph. Chat now grounds on these notes.")
                }
                Section {
                    Button("Import another folder") { viewModel.phase = .idle }
                }
            }
        }
        .navigationTitle("Import Vault")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $picking,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { Task { await viewModel.scan(url) } }
            case let .failure(error):
                viewModel.phase = .failed(error.localizedDescription)
            }
        }
    }

    private var chooseSection: some View {
        Section {
            Button {
                picking = true
            } label: {
                Label("Choose vault folder…", systemImage: "folder.badge.plus")
            }
        } footer: {
            Text("Pick your Obsidian / Hermes vault folder. Each top-level folder becomes a Space; its markdown is embedded for chat grounding and the Brain graph.")
        }
    }

    private var manifestSection: some View {
        Section {
            ForEach(viewModel.folders) { folder in
                Toggle(isOn: Binding(
                    get: { viewModel.selected.contains(folder.name) },
                    set: { _ in viewModel.toggle(folder.name) },
                )) {
                    HStack {
                        Text(folder.name).lineLimit(1)
                        Spacer()
                        Text("\(folder.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        } header: {
            Text("Folders to import")
        } footer: {
            Text("Large auto-generated folders are unchecked by default to keep the graph clean.")
        }
    }

    private var selectedCount: Int {
        viewModel.folders.filter { viewModel.selected.contains($0.name) }.reduce(0) { $0 + $1.count }
    }
}
