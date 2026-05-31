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
    let uploadClient: any VaultUploadClientProtocol

    @State private var fileToDelete: VaultFileDTO?
    @State private var fileToRename: VaultFileDTO?
    @State private var renameInput: String = ""
    @State private var filter: NoteFilter = .all

    enum NoteFilter: String, CaseIterable { case all = "All", notes = "Notes", todos = "Todos" }

    /// Applies the segmented filter and, for the Todos view, sorts open items
    /// by soonest due (undated last) and sinks completed ones to the bottom.
    private var displayedFiles: [VaultFileDTO] {
        let isTodo: (VaultFileDTO) -> Bool = { $0.metadata?.isTodo == true }
        switch filter {
        case .all:
            return vm.files
        case .notes:
            return vm.files.filter { !isTodo($0) }
        case .todos:
            return vm.files.filter(isTodo).sorted { a, b in
                let ad = a.metadata?.done == true, bd = b.metadata?.done == true
                if ad != bd { return !ad } // open before done
                let au = a.metadata?.dueAt ?? .distantFuture
                let bu = b.metadata?.dueAt ?? .distantFuture
                return au < bu
            }
        }
    }

    init(space: SpaceDTO, vaultClient: VaultClientProtocol, memoryClient: MemoryClientProtocol, uploadClient: any VaultUploadClientProtocol) {
        self.space = space
        self.vaultClient = vaultClient
        self.memoryClient = memoryClient
        self.uploadClient = uploadClient
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
            Picker("Filter", selection: $filter) {
                ForEach(NoteFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

            ForEach(displayedFiles) { file in
                NavigationLink {
                    MarkdownReaderView(file: file, vaultClient: vaultClient, memoryClient: memoryClient, uploadClient: uploadClient)
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
        let meta = file.metadata
        let isTodo = meta?.isTodo == true
        let done = meta?.done == true
        let title = meta?.title.flatMap { $0.isEmpty ? nil : $0 } ?? (file.path as NSString).lastPathComponent
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            if isTodo {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(palette.glowPrimary)
                    .font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .strikethrough(done, color: palette.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let due = meta?.dueAt {
                        Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.glowPrimary)
                    } else {
                        Text(file.path)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(byteCount(file.sizeBytes))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.lvTextMuted)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        LVEmptyState(
            mascot: .idle,
            headline: "No files in this space yet.",
            supporting: "Capture your first memory or note from the Home tab.",
            backgroundImage: "Lumina/Mascot/winged-scroll-vault"
        )
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
