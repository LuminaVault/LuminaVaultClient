// LuminaVaultClient/LuminaVaultClient/Features/Spaces/SpacesListView.swift
// HER-35: home tab post-vault-create. Renders a search bar, segmented
// category control, LazyVGrid of SpaceCardView, and a FAB to create new
// Spaces. Long-press menus fire edit/delete via the shared editor sheet.
// HER-105: each Space card is now a NavigationLink → `VaultFilesListView`
// (three-pane browser); the magnifying-glass toolbar item opens the
// universal search sheet (`VaultSearchView`).
import SwiftUI

struct SpacesListView: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: SpacesViewModel
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryQueryClientProtocol
    let memoryDetailClient: MemoryClientProtocol

    @State private var presentingEditorFor: EditorPresentation?
    @State private var spaceToDelete: SpaceDTO?
    @State private var presentingSearch = false
    @State private var searchVM: VaultSearchViewModel

    init(
        vm: SpacesViewModel,
        vaultClient: VaultClientProtocol,
        memoryClient: MemoryQueryClientProtocol,
        memoryDetailClient: MemoryClientProtocol,
    ) {
        self._vm = Bindable(wrappedValue: vm)
        self.vaultClient = vaultClient
        self.memoryClient = memoryClient
        self.memoryDetailClient = memoryDetailClient
        self._searchVM = State(wrappedValue: VaultSearchViewModel(
            memoryClient: memoryClient, vaultClient: vaultClient,
        ))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                // Background
                Color.black.ignoresSafeArea()
                
                // Cosmic aurora gradients
                RadialGradient(
                    colors: [palette.glowPrimary.opacity(0.15), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 600
                ).ignoresSafeArea()
                
                RadialGradient(
                    colors: [palette.accent.opacity(0.1), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 500
                ).ignoresSafeArea()
                
                content
                createButton
            }
            .safeAreaInset(edge: .top) {
                LuminaHeader(title: "Spaces")
            }
            .lvBackground()
            .toolbar(.hidden, for: .navigationBar) // Custom header instead
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
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 24) {
                searchField
                
                if !vm.categories.isEmpty && vm.categories.count > 1 {
                    categoryChips
                }

                if let error = vm.error {
                    errorBanner(message: error)
                }

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
            .padding(.top, 40)
            .padding(.bottom, 120)
        }
    }

    private var headerSection: some View {
        HStack {
            Text("Spaces")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .shadow(color: palette.glowPrimary.opacity(0.8), radius: 12)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(palette.textSecondary)
            
            TextField("Search spaces", text: $vm.searchQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(palette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(palette.surfaceStroke, lineWidth: 1)
                }
        }
        .padding(.horizontal, 20)
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

    private var createButton: some View {
        Button {
            presentingEditorFor = EditorPresentation(mode: .create)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.black)
                .frame(width: 64, height: 64)
                .background {
                    Circle()
                        .fill(palette.glowPrimary)
                        .shadow(color: palette.glowPrimary.opacity(0.6), radius: 15)
                }
                .lvGlowPress()
        }
        .padding(24)
        .padding(.bottom, 16)
    }

    private var emptyState: some View {
        LVEmptyState(
            mascot: .idle,
            headline: "Your vault is ready.",
            supporting: "Tap the + button to capture your first space.",
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
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
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
