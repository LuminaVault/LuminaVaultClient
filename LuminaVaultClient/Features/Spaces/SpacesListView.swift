// LuminaVaultClient/LuminaVaultClient/Features/Spaces/SpacesListView.swift
// HER-35: the Spaces tab. A category control and a LazyVGrid of
// SpaceCardView; long-press menus fire edit/delete via the shared editor
// sheet. HER-105: each Space card is a NavigationLink → `VaultFilesListView`
// (three-pane browser).
//
// The chrome is the system's: `.searchable` for the filter, the capture "+"
// and an overflow `…` in the navigation bar for New Space and visual search.
// The floating create button and the particle field it sat on are gone.
import SwiftUI

struct SpacesListView: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: SpacesViewModel
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryQueryClientProtocol
    let memoryDetailClient: MemoryClientProtocol
    let uploadClient: any VaultUploadClientProtocol

    @State private var presentingEditorFor: EditorPresentation?
    @State private var spaceToDelete: SpaceDTO?
    @State private var presentingSearch = false
    @State private var searchVM: VaultSearchViewModel
    /// Drives the push to `VisualSearchView` from the `…` menu. A
    /// `NavigationLink` inside a `Menu` does not reliably push, and the menu
    /// must not present — `MainTabView`'s chained sheets already drop a
    /// second presentation.
    @State private var showingVisualSearch = false

    init(
        vm: SpacesViewModel,
        vaultClient: VaultClientProtocol,
        memoryClient: MemoryQueryClientProtocol,
        memoryDetailClient: MemoryClientProtocol,
        uploadClient: any VaultUploadClientProtocol,
    ) {
        self._vm = Bindable(wrappedValue: vm)
        self.vaultClient = vaultClient
        self.memoryClient = memoryClient
        self.memoryDetailClient = memoryDetailClient
        self.uploadClient = uploadClient
        self._searchVM = State(wrappedValue: VaultSearchViewModel(
            memoryClient: memoryClient, vaultClient: vaultClient,
        ))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        content
            .lvBackground()
            .searchable(text: $vm.searchQuery, prompt: "Search spaces")
            // Declared before `captureToolbarItem()` so the bar reads
            // "+" then "…": trailing items land right-to-left in the order
            // their modifiers are applied.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { spacesMenu }
            }
            .captureToolbarItem()
            .navigationDestination(isPresented: $showingVisualSearch) {
                VisualSearchView(
                    viewModel: VisualSearchViewModel(
                        ocr: ImageOCRService(),
                        client: memoryClient,
                        telemetry: AnalyticsTelemetry()
                    )
                )
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .alert("Delete space?",
                   isPresented: Binding(
                    get: { spaceToDelete != nil },
                    set: { if !$0 { spaceToDelete = nil } }
                   ),
                   presenting: spaceToDelete,
                   actions: { space in
                       Button("Delete", role: .destructive) {
                           Task { await vm.delete(id: space.id) }
                           spaceToDelete = nil
                       }
                       Button("Cancel", role: .cancel) {
                           spaceToDelete = nil
                       }
                   },
                   message: { space in
                       Text("\"\(space.name)\" will be removed. Notes stored under this space stay on disk in a `_deleted_…` folder.")
                   })
            .sheet(item: $presentingEditorFor) { presentation in
                SpaceEditorSheet(
                    mode: presentation.mode,
                    knownCategories: vm.categories,
                    onSubmit: { payload in
                        switch presentation.mode {
                        case .create:
                            await vm.create(CreateSpaceRequest(
                                name: payload.name,
                                slug: payload.slug,
                                description: nil,
                                color: payload.color,
                                icon: payload.icon,
                                category: payload.category,
                            ))
                        case let .edit(existing):
                            await vm.update(id: existing.id, UpdateSpaceRequest(
                                name: payload.name,
                                description: nil,
                                color: payload.color,
                                icon: payload.icon,
                                category: payload.category ?? "",
                            ))
                        }
                    },
                )
            }
            .sheet(isPresented: $presentingSearch) {
                VaultSearchView(vm: searchVM, vaultClient: vaultClient, memoryClient: memoryDetailClient)
            }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !vm.categories.isEmpty && vm.categories.count > 1 {
                    categoryChips
                }

                if let error = vm.error {
                    errorBanner(message: error)
                }

                inboxCard

                if vm.isLoading && vm.spaces.isEmpty {
                    ProgressView()
                        .tint(palette.glowPrimary)
                        .padding(.top, 60)
                } else if vm.visibleSpaces.isEmpty {
                    if vm.error != nil {
                        errorEmptyState
                    } else {
                        emptyState
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(vm.visibleSpaces) { space in
                            NavigationLink {
                                VaultFilesListView(
                                    space: space,
                                    vaultClient: vaultClient,
                                    memoryClient: memoryDetailClient,
                                    uploadClient: uploadClient,
                                )
                            } label: {
                                SpaceCardView(
                                    space: space,
                                    onEdit: { presentingEditorFor = EditorPresentation(mode: .edit(space)) },
                                    onDelete: { spaceToDelete = space },
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 16)
        }
    }

    /// The tab's overflow. "New Space" used to be a floating button over the
    /// tab bar; both actions now live where iOS puts a screen's own verbs.
    private var spacesMenu: some View {
        Menu {
            Button("New Space", systemImage: "plus") {
                presentingEditorFor = EditorPresentation(mode: .create)
            }
            Button("Search by photo", systemImage: "photo.on.rectangle.angled") {
                showingVisualSearch = true
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(vm.categories, id: \.self) { cat in
                    let isSelected = vm.selectedCategory == cat
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            vm.selectedCategory = cat
                        }
                    } label: {
                        Text(cat == allCategoriesSlug ? "All" : cat.capitalized)
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(palette.glowPrimary)
                                        .shadow(color: palette.glowPrimary.opacity(0.5), radius: 8)
                                } else {
                                    Capsule()
                                        .fill(palette.surface)
                                        .overlay {
                                            Capsule()
                                                .stroke(palette.surfaceStroke, lineWidth: 1)
                                        }
                                }
                            }
                            .foregroundStyle(isSelected ? .black : palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// Synthetic Space backing the Inbox bucket. `slug = "inbox"` is a
    /// reserved server sentinel — `GET /v1/vault/files?space=inbox` returns
    /// unfiled notes (space_id IS NULL) instead of resolving a real Space.
    /// Fixed id so the NavigationLink identity is stable across renders.
    static let inboxSpace = SpaceDTO(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B0")!,
        name: "Inbox",
        slug: "inbox",
        icon: "folder",
    )

    /// Full-width card collecting unfiled notes — the catch-all every note
    /// lands in when no Space is chosen. Always visible so the backlog is
    /// reachable even before the user creates any Space.
    private var inboxCard: some View {
        NavigationLink {
            VaultFilesListView(
                space: Self.inboxSpace,
                vaultClient: vaultClient,
                memoryClient: memoryDetailClient,
                uploadClient: uploadClient,
            )
        } label: {
            HStack(spacing: 16) {
                LVIconView(.layers, size: 32, tint: palette.glowPrimary, weight: .light)
                    .shadow(color: palette.glowPrimary.opacity(0.6), radius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inbox")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Unfiled notes")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.glowPrimary)
                }
                Spacer()
                LVIconView(.chevronRight, size: 16, tint: palette.textSecondary, weight: .semibold)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lvGlassCard(cornerRadius: 24, intensity: 0.7)
            .lvGlowStroke(cornerRadius: 24, intensity: LVGlow.card)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        LVEmptyState(
            mascot: .idle,
            headline: "Your vault is ready.",
            supporting: "Create your first space to file notes under.",
            primaryCTA: ("New Space", { presentingEditorFor = EditorPresentation(mode: .create) }),
            chips: [],
            backgroundImage: "Lumina/Backgrounds/neural-network"
        )
        .padding(.top, 32)
    }

    private var errorEmptyState: some View {
        LVEmptyState(
            mascot: .thinking,
            headline: "Can't reach the server.",
            supporting: vm.error,
            primaryCTA: ("Retry", { Task { await vm.load() } }),
            chips: []
        )
        .padding(.top, 32)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            LVIconView(.exclamationmarkTriangleFill, size: 12, tint: .red)
            Text(message)
                .font(.caption.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.18))
        .foregroundStyle(.red)
    }
}

private struct EditorPresentation: Identifiable {
    let id = UUID()
    let mode: SpaceEditorSheet.Mode
}
