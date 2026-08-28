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

    /// Hoisted out of `byteCount(_:)`, which the row builder calls for every
    /// row on every body pass. `ByteCountFormatter.string(fromByteCount:…)`
    /// builds and discards a formatter on each call.
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

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
            Picker("Filter", selection: $vm.filter) {
                ForEach(VaultFilesViewModel.NoteFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

            ForEach(vm.displayedFiles) { file in
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
            }

            if vm.displayedFiles.isEmpty {
                Text(emptyFilterMessage)
                    .lvFont(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .listRowBackground(Color.clear)
            }

            // Pagination sentinel. This used to hang off the last row's
            // `.onAppear` compared against `vm.files.last` — which is the last
            // *fetched* file, not the last *displayed* one, so under the Notes
            // or Todos filter the trigger row was usually never rendered and
            // pagination stopped silently. A footer row also keeps paging when
            // the current filter matches nothing on the pages fetched so far.
            if vm.nextCursor != nil {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
                    .onAppear { Task { await vm.loadMore() } }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyFilterMessage: String {
        switch vm.filter {
        case .all: return "No files in this space."
        case .notes: return "No notes in this space."
        case .todos: return "No todos in this space."
        }
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
        Self.byteFormatter.string(fromByteCount: bytes)
    }
}
