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

    @State private var presentingEditorFor: EditorPresentation?
    @State private var spaceToDelete: SpaceDTO?
    @State private var presentingSearch = false
    @State private var searchVM: VaultSearchViewModel

    init(vm: SpacesViewModel, vaultClient: VaultClientProtocol, memoryClient: MemoryQueryClientProtocol) {
        self._vm = Bindable(wrappedValue: vm)
        self.vaultClient = vaultClient
        self.memoryClient = memoryClient
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
                content
                createButton
            }
            .navigationTitle("Spaces")
            .lvBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(palette.primary)
                    }
                }
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
                VaultSearchView(vm: searchVM, vaultClient: vaultClient)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                searchField
                categoryChips
                if let error = vm.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }
                if vm.isLoading && vm.spaces.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if vm.visibleSpaces.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(vm.visibleSpaces) { space in
                            NavigationLink {
                                VaultFilesListView(space: space, vaultClient: vaultClient)
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
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 96)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search spaces", text: $vm.searchQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.backgroundBase.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.categories, id: \.self) { cat in
                    let isSelected = vm.selectedCategory == cat
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.selectedCategory = cat
                        }
                    } label: {
                        Text(cat == allCategoriesSlug ? "All" : cat.capitalized)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? palette.primary : palette.backgroundBase.opacity(0.5))
                            .foregroundStyle(isSelected ? .black : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No spaces yet")
                .font(.system(size: 16, weight: .semibold))
            Text("Tap “New Space” to start organising memories.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
    }

    private var createButton: some View {
        Button {
            presentingEditorFor = EditorPresentation(mode: .create)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(
                        colors: [palette.primary, palette.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    )
                )
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .padding(20)
    }
}

private struct EditorPresentation: Identifiable {
    let id = UUID()
    let mode: SpaceEditorSheet.Mode
}
