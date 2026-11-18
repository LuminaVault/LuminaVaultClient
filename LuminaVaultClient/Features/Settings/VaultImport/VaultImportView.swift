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
    private let client: VaultImportClientProtocol

    init(client: VaultImportClientProtocol) {
        self.client = client
        _viewModel = State(initialValue: VaultImportViewModel(client: client))
    }

    var body: some View {
        Form {
            switch viewModel.phase {
            case .idle:
                chooseSection
                notionSection
            case let .failed(message):
                chooseSection
                Section {
                    Text(message).foregroundStyle(.red).font(.footnote)
                }
                notionSection
            case .scanning:
                Section {
                    HStack(spacing: 12) { ProgressView(); Text("Scanning folder…") }
                }
            case .manifest:
                manifestSection
                Section {
                    Toggle("Keep notes already in LuminaVault", isOn: $viewModel.keepExisting)
                } footer: {
                    Text(viewModel.keepExisting
                        ? "A note with the same name stays as it is, and is listed after the import."
                        : "A note with the same name is replaced by the vault's version.")
                }
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
                if !viewModel.needsAttention.isEmpty {
                    Section("Notes to check") {
                        ForEach(viewModel.needsAttention.prefix(50), id: \.path) { file in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.path).font(.footnote.monospaced()).lineLimit(1)
                                Text(Self.attentionLabel(file)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
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

    private static func attentionLabel(_ file: VaultBulkFileResult) -> String {
        switch file.status {
        case "exists": "Kept your note\(file.savedPath.map { " at \($0)" } ?? "")"
        case "collision": "Same name as another note in this folder; the first was imported"
        default: "Could not be imported"
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
            Text("Pick your Obsidian / Hermes vault folder. Each top-level folder becomes a Space, and notes at the top of the vault go to a Space named after it. Links between notes keep working. Obsidian settings and attachments are left out.")
        }
    }

    /// E7.4: a Notion export is one ZIP the server unpacks, a different flow
    /// from the folder read above, so it gets a screen of its own.
    private var notionSection: some View {
        Section {
            NavigationLink {
                NotionImportView(client: client)
            } label: {
                Label("Import from Notion…", systemImage: "doc.zipper")
            }
        } footer: {
            Text("Coming from Notion? Import its export ZIP, with pages, links, attachments and databases.")
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
