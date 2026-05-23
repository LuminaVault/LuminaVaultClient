// LuminaVaultClient/LuminaVaultClient/Features/Vault/VaultFilesListView.swift
// HER-105: middle pane of the three-pane vault browser (Spaces → Files →
// Reader). Renders the files inside a Space with pull-to-refresh, an
// empty-state nudge, and a long-press context menu (move / delete /
// share).
import SwiftUI

struct VaultFilesListView: View {

    @Environment(\.lvPalette) private var palette

    let space: SpaceDTO
    @Bindable var vm: VaultFilesViewModel
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol

    @State private var fileToDelete: VaultFileDTO?
    @State private var fileToRename: VaultFileDTO?
    @State private var renameInput: String = ""

    init(space: SpaceDTO, vaultClient: VaultClientProtocol, memoryClient: MemoryClientProtocol) {
        self.space = space
        self.vaultClient = vaultClient
        self.memoryClient = memoryClient
        self._vm = Bindable(wrappedValue: VaultFilesViewModel(vaultClient: vaultClient, spaceSlug: space.slug))
    }

    var body: some View {
        content
            .navigationTitle(space.name)
            .navigationBarTitleDisplayMode(.inline)
            .lvBackground()
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .alert("Delete file?",
                   isPresented: Binding(
                       get: { fileToDelete != nil },
                       set: { if !$0 { fileToDelete = nil } }
                   ),
                   presenting: fileToDelete) { file in
                Button("Delete", role: .destructive) {
                    Task { await vm.delete(file: file) }
                    fileToDelete = nil
                }
                Button("Cancel", role: .cancel) { fileToDelete = nil }
            } message: { file in
                Text("\(file.path) will be moved to the soft-deleted bin.")
            }
            .alert("Move file",
                   isPresented: Binding(
                       get: { fileToRename != nil },
                       set: { if !$0 { fileToRename = nil } }
                   ),
                   presenting: fileToRename) { file in
                TextField("New path", text: $renameInput)
                Button("Move") {
                    let target = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !target.isEmpty {
                        Task { await vm.move(file: file, newPath: target) }
                    }
                    fileToRename = nil
                }
                Button("Cancel", role: .cancel) { fileToRename = nil }
            } message: { file in
                Text("Current path: \(file.path)")
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.files.isEmpty {
            ProgressView().controlSize(.large)
        } else if vm.files.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(vm.files) { file in
                NavigationLink {
                    MarkdownReaderView(file: file, vaultClient: vaultClient, memoryClient: memoryClient)
                } label: {
                    fileRow(file)
                }
                .contextMenu {
                    Button {
                        renameInput = file.path
                        fileToRename = file
                    } label: { Label("Move…", systemImage: "arrow.up.right.square") }
                    ShareLink(item: file.path) {
                        Label("Share path", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        fileToDelete = file
                    } label: { Label("Delete", systemImage: "trash") }
                }
                .listRowBackground(Color.clear)
                .onAppear {
                    if file.id == vm.files.last?.id {
                        Task { await vm.loadMore() }
                    }
                }
            }
            if vm.isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func fileRow(_ file: VaultFileDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((file.path as NSString).lastPathComponent)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(file.path)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(byteCount(file.sizeBytes))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lvTextMuted)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        LVEmptyState(
            mascot: .idle,
            headline: "No files in this space yet.",
            supporting: "Capture your first memory or note from the Home tab."
        )
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
