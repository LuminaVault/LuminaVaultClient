// LuminaVaultClient/LuminaVaultClient/Features/Vault/VaultViewsView.swift
// Backlog E8.5: the vault's saved views (made on the web) and each one as a
// read-only table. Reached from the vault toolbar only while properties are
// on; tapping a row opens the note.
import SwiftUI

struct VaultViewsListView: View {
    @Environment(\.lvPalette) private var palette

    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol
    let uploadClient: any VaultUploadClientProtocol

    @State private var views: [VaultSavedView] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && views.isEmpty {
                ProgressView().controlSize(.large)
            } else if let error {
                ContentUnavailableView {
                    Label("Views unavailable", systemImage: "tablecells")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else if views.isEmpty {
                ContentUnavailableView(
                    "No saved views",
                    systemImage: "tablecells",
                    description: Text("Make a view on the web: pick a folder or tag in the Table, then save it.")
                )
            } else {
                List(views) { view in
                    NavigationLink {
                        VaultViewTableView(
                            model: VaultViewTableModel(view: view, vaultClient: vaultClient),
                            vaultClient: vaultClient,
                            memoryClient: memoryClient,
                            uploadClient: uploadClient
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(view.name).lvFont(.body).foregroundStyle(palette.textPrimary)
                            Text(Self.scopeLabel(view.scope))
                                .font(.system(size: 12))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Views")
        .navigationBarTitleDisplayMode(.inline)
        .lvBackground()
        .task { await load() }
        .refreshable { await load() }
    }

    static func scopeLabel(_ scope: VaultQueryScope) -> String {
        var parts: [String] = []
        if let folder = scope.folder, !folder.isEmpty {
            parts.append("\(folder)/")
        }
        if let tag = scope.tag, !tag.isEmpty {
            parts.append("#\(tag)")
        }
        if scope.spaceId?.isEmpty == false {
            parts.append("a Space")
        }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            views = try await vaultClient.listViews().sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            error = nil
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct VaultViewTableView: View {
    @Environment(\.lvPalette) private var palette

    @State var model: VaultViewTableModel
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol
    let uploadClient: any VaultUploadClientProtocol

    private let nameWidth: CGFloat = 160
    private let cellWidth: CGFloat = 140

    var body: some View {
        Group {
            if model.isLoading && model.rows.isEmpty {
                ProgressView().controlSize(.large)
            } else if let error = model.error, model.rows.isEmpty {
                ContentUnavailableView {
                    Label("Table unavailable", systemImage: "tablecells")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") { Task { await model.load() } }
                }
            } else if model.hasLoaded && model.rows.isEmpty {
                ContentUnavailableView(
                    "No notes in this view",
                    systemImage: "tablecells",
                    description: Text("No Markdown note matches its scope and filters.")
                )
            } else {
                table
            }
        }
        .navigationTitle(model.view.name)
        .navigationBarTitleDisplayMode(.inline)
        .lvBackground()
        .task {
            if !model.hasLoaded {
                await model.load()
            }
        }
        .refreshable { await model.load() }
    }

    private var table: some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header
                    ForEach(model.sections) { section in
                        Section {
                            ForEach(section.rows, id: \.file.id) { row in
                                tableRow(row)
                            }
                        } header: {
                            if let title = section.title {
                                HStack(spacing: 6) {
                                    Text(title).font(.system(size: 12, weight: .semibold))
                                    if let count = section.count {
                                        Text("\(count)").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.surface)
                                .accessibilityAddTraits(.isHeader)
                            }
                        }
                    }
                    if model.nextCursor != nil {
                        Button {
                            Task { await model.loadMore() }
                        } label: {
                            if model.isLoadingMore {
                                ProgressView()
                            } else {
                                Text("Load more")
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Note").frame(width: nameWidth, alignment: .leading)
            ForEach(model.columns) { column in
                Text(column.name).frame(width: cellWidth, alignment: .leading).lineLimit(1)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func tableRow(_ row: VaultQueryRow) -> some View {
        NavigationLink {
            MarkdownReaderView(
                file: row.file,
                vaultClient: vaultClient,
                memoryClient: memoryClient,
                uploadClient: uploadClient
            )
        } label: {
            HStack(spacing: 0) {
                Text(Self.noteName(row.file.path))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .frame(width: nameWidth, alignment: .leading)
                ForEach(model.columns) { column in
                    NotePropertyValueView(row: NotePropertyRow(
                        name: column.name,
                        kind: column.kind,
                        value: row.properties[column.name] ?? .null
                    ))
                    .lineLimit(1)
                    .frame(width: cellWidth, alignment: .leading)
                    .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.noteName(row.file.path))
        .overlay(alignment: .bottom) { Divider().background(palette.surfaceStroke) }
    }

    static func noteName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name
    }
}
