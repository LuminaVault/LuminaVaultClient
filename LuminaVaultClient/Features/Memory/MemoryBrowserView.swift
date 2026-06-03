// LuminaVaultClient/LuminaVaultClient/Features/Memory/MemoryBrowserView.swift
//
// Phase 2 — Settings → Your Agent → Memories. Browse, search, edit, and
// delete the memories your agent recalls. Read/write over /v1/memory.

import LuminaVaultShared
import SwiftUI

struct MemoryBrowserView: View {
    @State private var viewModel: MemoryBrowserViewModel

    init(client: any MemoryClientProtocol) {
        _viewModel = State(initialValue: MemoryBrowserViewModel(client: client))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                listContent
            case let .failed(message):
                VStack(spacing: 12) {
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await viewModel.load() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Memories")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.query, prompt: "Search memories")
        .onSubmit(of: .search) { Task { await viewModel.runSearch() } }
        .onChange(of: viewModel.query) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, viewModel.isSearching {
                Task { await viewModel.load() }
            }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder private var listContent: some View {
        List {
            if let error = viewModel.actionError {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }
            if viewModel.memories.isEmpty {
                Section {
                    Text(viewModel.isSearching ? "No matches." : "No memories yet.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(viewModel.memories, id: \.id) { memory in
                NavigationLink {
                    MemoryEditView(viewModel: viewModel, memory: memory)
                } label: {
                    row(memory)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await viewModel.delete(memory) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            if viewModel.canLoadMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .task { await viewModel.loadMore() }
            }
        }
    }

    private func row(_ memory: MemoryDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(memory.content)
                .lineLimit(2)
                .font(.body)
            HStack(spacing: 8) {
                if let created = memory.createdAt {
                    Text(created.formatted(.relative(presentation: .named)))
                }
                if !memory.tags.isEmpty {
                    Text("· " + memory.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Edit a single memory's content + tags.
private struct MemoryEditView: View {
    let viewModel: MemoryBrowserViewModel
    let memory: MemoryDTO

    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var tagsText: String
    @State private var isSaving = false

    init(viewModel: MemoryBrowserViewModel, memory: MemoryDTO) {
        self.viewModel = viewModel
        self.memory = memory
        _content = State(initialValue: memory.content)
        _tagsText = State(initialValue: memory.tags.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section("Content") {
                TextEditor(text: $content)
                    .frame(minHeight: 160)
                    .disabled(isSaving)
            }
            Section("Tags") {
                TextField("comma, separated, tags", text: $tagsText)
                    .disabled(isSaving)
            }
            if let created = memory.createdAt {
                Section {
                    LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .navigationTitle("Edit memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        isSaving = true
                        let ok = await viewModel.save(id: memory.id, content: content, tags: parsedTags)
                        isSaving = false
                        if ok { dismiss() }
                    }
                }
                .disabled(isSaving || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var parsedTags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
