// LuminaVaultClient/LuminaVaultClient/Features/Memory/MemoryDetailSheet.swift
//
// One memory by id, as a sheet (`MemoryDetailSheet`) or pushed inside one
// (`MemoryDetailView`). Shows the content, its kind, date and Space, where it
// came from, and what it connects to; edits through the same editor the
// memory browser uses, and deletes behind a confirmation.

import LuminaVaultShared
import SwiftUI

/// The sheet: its own `NavigationStack`, so related memories push inside it.
struct MemoryDetailSheet: View {
    let memoryID: UUID
    let client: any MemoryClientProtocol
    var spacesClient: (any SpacesClientProtocol)?
    /// Called after a delete, before the sheet closes.
    var onDeleted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MemoryDetailView(
                memoryID: memoryID,
                client: client,
                spacesClient: spacesClient,
                onDeleted: onDeleted
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The screen. Pushable, so a related memory opens another one of these on
/// the same stack and Back returns to where you were.
struct MemoryDetailView: View {
    @State private var vm: MemoryDetailViewModel
    @State private var editor: MemoryBrowserViewModel?
    @State private var isEditing = false
    @State private var confirmingDelete = false
    /// Bumped when the editor closes, so the memory is re-read.
    @State private var reloadToken = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    private let client: any MemoryClientProtocol
    private let spacesClient: (any SpacesClientProtocol)?
    private let onDeleted: (() -> Void)?

    init(
        memoryID: UUID,
        client: any MemoryClientProtocol,
        spacesClient: (any SpacesClientProtocol)? = nil,
        onDeleted: (() -> Void)? = nil
    ) {
        _vm = State(initialValue: MemoryDetailViewModel(
            memoryID: memoryID,
            client: client,
            spacesClient: spacesClient
        ))
        self.client = client
        self.spacesClient = spacesClient
        self.onDeleted = onDeleted
    }

    var body: some View {
        content
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if vm.memory != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") {
                            if editor == nil { editor = vm.makeEditor() }
                            isEditing = true
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $isEditing) {
                if let editor, let memory = vm.memory {
                    MemoryEditView(viewModel: editor, memory: memory)
                        .task { await editor.loadSpacesIfNeeded() }
                }
            }
            .onChange(of: isEditing) { _, editing in
                if !editing { reloadToken += 1 }
            }
            .task(id: reloadToken) {
                if reloadToken == 0 {
                    await vm.load()
                } else {
                    await vm.reload()
                }
            }
            .confirmationDialog(
                "Delete this memory?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        if await vm.delete() {
                            onDeleted?()
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Lumina will stop recalling it. This can't be undone.")
            }
    }

    @ViewBuilder private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label(message, systemImage: "exclamationmark.triangle")
            } actions: {
                Button("Try again") { Task { await vm.load() } }
            }
        case let .loaded(memory):
            loaded(memory)
        }
    }

    private func loaded(_ memory: MemoryDTO) -> some View {
        List {
            if let error = vm.actionError {
                Section {
                    Text(error)
                        .lvFont(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text(memory.content)
                    .lvFont(.body)
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .padding(.vertical, LVSpacing.xs)
            }

            Section("Details") {
                if let kind = memory.kind {
                    LabeledContent("Kind") { MemoryKindChip(kind: kind) }
                }
                if let created = memory.createdAt {
                    LabeledContent("Saved", value: created.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Space", value: vm.spaceName(memory.spaceId) ?? (memory.spaceId == nil ? "Inbox" : "A Space"))
                if !memory.tags.isEmpty {
                    LabeledContent("Tags", value: memory.tags.map { "#\($0)" }.joined(separator: " "))
                }
            }

            if !vm.provenanceFailed {
                MemoryProvenanceSection(response: vm.provenance)
            }

            relatedSection

            Section {
                Button("Delete memory", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
                .disabled(vm.isDeleting)
            }
        }
    }

    @ViewBuilder private var relatedSection: some View {
        switch vm.related {
        case .loading:
            Section("Connects to") {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        case let .loaded(items) where items.isEmpty:
            Section("Connects to") {
                Text("Nothing connected yet. Keep saving and Lumina will link related memories.")
                    .lvFont(.footnote)
                    .foregroundStyle(.secondary)
            }
        case let .loaded(items):
            Section("Connects to") {
                ForEach(items) { item in
                    NavigationLink {
                        MemoryDetailView(memoryID: item.id, client: client, spacesClient: spacesClient)
                    } label: {
                        RelatedMemoryRow(item: item)
                    }
                }
            }
        case .failed:
            EmptyView()
        }
    }
}
