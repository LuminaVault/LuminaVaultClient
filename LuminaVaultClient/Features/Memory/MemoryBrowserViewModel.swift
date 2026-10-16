// LuminaVaultClient/LuminaVaultClient/Features/Memory/MemoryBrowserViewModel.swift
//
// Phase 2 — direct memory management. Lists the tenant's memories
// (paged), runs semantic search, and supports edit (content/tags) + delete
// over the existing /v1/memory CRUD endpoints.

import Foundation
import WidgetKit
import LuminaVaultShared

@MainActor
@Observable
final class MemoryBrowserViewModel {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private let client: any MemoryClientProtocol
    private let routerClient: (any RouterClientProtocol)?
    private let conversationsClient: (any ConversationsClientProtocol)?
    /// Mirrors loaded memories into the on-device Spotlight index so vault
    /// content is findable from iOS Search. Best-effort and non-blocking —
    /// indexing must never delay or fail a list load.
    private let spotlight: SpotlightIndexer?
    private let spacesClient: (any SpacesClientProtocol)?
    /// For the Space picker and the Space name on each row. Empty without a
    /// Spaces client, which hides the picker.
    private(set) var spaces: [SpaceDTO] = []
    let healthFilter: MemoryHealthFilter?
    /// Narrows the list to one kind; nil shows everything.
    private(set) var kindFilter: MemoryKindDTO?
    private let pageSize = 50

    var state: LoadState = .loading
    private(set) var memories: [MemoryDTO] = []
    private(set) var canLoadMore = false
    private var offset = 0

    /// Search query. Empty = browse mode (paged list); non-empty after a
    /// submit = search-result mode.
    var query: String = ""
    private(set) var isSearching = false
    var actionError: String?
    private(set) var provenanceByMemoryID: [UUID: MemoryProvenanceResponse] = [:]
    private(set) var routesByMemoryID: [UUID: [RouterModelRouteDTO]] = [:]
    private(set) var isLoadingDetails = false

    init(
        client: any MemoryClientProtocol,
        routerClient: (any RouterClientProtocol)? = nil,
        conversationsClient: (any ConversationsClientProtocol)? = nil,
        spotlight: SpotlightIndexer? = nil,
        healthFilter: MemoryHealthFilter? = nil,
        spacesClient: (any SpacesClientProtocol)? = nil
    ) {
        self.client = client
        self.routerClient = routerClient
        self.conversationsClient = conversationsClient
        self.spotlight = spotlight
        self.healthFilter = healthFilter
        self.spacesClient = spacesClient
    }

    func spaceName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return spaces.first { $0.id == id }?.name
    }

    /// Files a memory in a Space, or (nil) takes it out of every Space. A
    /// memory that came from a note moves with its note — the server does
    /// that, so the note never ends up in a different Space from its memory.
    func move(id: UUID, toSpace spaceID: UUID?) async -> Bool {
        do {
            let updated = try await client.patch(
                id: id,
                MemoryPatchRequest(spaceId: spaceID.map { .space($0) } ?? .unfiled)
            )
            if let idx = memories.firstIndex(where: { $0.id == id }) {
                memories[idx] = updated
            }
            return true
        } catch {
            actionError = "Couldn't move that memory."
            return false
        }
    }

    /// The Space list on its own, for an editor opened outside the browser
    /// (the memory detail sheet), which has no page of memories to load.
    func loadSpacesIfNeeded() async {
        guard spaces.isEmpty, let spacesClient else { return }
        spaces = (try? await spacesClient.list()) ?? []
    }

    func load() async {
        await loadSpacesIfNeeded()
        state = .loading
        offset = 0
        isSearching = false
        actionError = nil
        do {
            let response = try await client.list(limit: pageSize, offset: 0, healthFilter: healthFilter, kind: kindFilter)
            memories = response.memories
            offset = response.memories.count
            canLoadMore = response.memories.count == pageSize
            state = .ready
            indexInSpotlight(response.memories)
            publishWidgetSnapshot()
        } catch {
            state = .failed("Couldn't load your memories.")
        }
    }

    func loadMore() async {
        guard canLoadMore, !isSearching, state == .ready else { return }
        do {
            let response = try await client.list(limit: pageSize, offset: offset, healthFilter: healthFilter, kind: kindFilter)
            memories.append(contentsOf: response.memories)
            offset += response.memories.count
            canLoadMore = response.memories.count == pageSize
            indexInSpotlight(response.memories)
        } catch {
            actionError = "Couldn't load more."
        }
    }

    func setKindFilter(_ kind: MemoryKindDTO?) async {
        guard kind != kindFilter else { return }
        kindFilter = kind
        query = ""
        await load()
    }

    func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await load()
            return
        }
        state = .loading
        isSearching = true
        actionError = nil
        do {
            let response = try await client.search(MemorySearchRequest(query: trimmed, limit: pageSize))
            // Hydrate hits into full MemoryDTOs we can edit/delete inline.
            memories = response.hits.map {
                MemoryDTO(
                    id: $0.id,
                    content: $0.content,
                    tags: [],
                    createdAt: $0.createdAt,
                    reviewState: "approved"
                )
            }
            canLoadMore = false
            state = .ready
        } catch {
            state = .failed("Search failed.")
        }
    }

    /// Fire-and-forget so a slow index write never stalls the list.
    private func indexInSpotlight(_ memories: [MemoryDTO]) {
        guard let spotlight, !memories.isEmpty else { return }
        Task { await spotlight.index(memories: memories) }
    }

    /// Publishes the newest memories to the App Group file the home-screen
    /// widget reads. The widget process holds no bearer token and cannot call
    /// the API itself, so if the app never writes this the widget is
    /// permanently empty — the same dead-on-arrival shape HealthKit had.
    ///
    /// Uses `self.memories` rather than the incoming page so a `loadMore`
    /// doesn't publish page 2 as if it were the newest items.
    private func publishWidgetSnapshot() {
        let items = memories.prefix(WidgetSnapshotStore.maxItems).map { memory in
            WidgetCaptureItem(
                id: memory.id,
                title: SpotlightIndexer.title(for: memory),
                createdAt: memory.createdAt ?? Date(),
                placeName: memory.placeName
            )
        }
        WidgetSnapshotStore.write(WidgetSnapshot(
            items: Array(items),
            totalCount: memories.count,
            updatedAt: Date()
        ))
        WidgetCenter.shared.reloadTimelines(ofKind: "LuminaVaultWidgets")
    }

    func delete(_ memory: MemoryDTO) async {
        do {
            try await client.delete(id: memory.id)
            memories.removeAll { $0.id == memory.id }
            // Drop it from Search too, or a deleted note stays findable.
            if let spotlight {
                Task { await spotlight.remove(memoryIDs: [memory.id]) }
            }
            publishWidgetSnapshot()
        } catch {
            actionError = "Couldn't delete that memory."
        }
    }

    /// Saves an edited memory (content, tags, kind) and replaces the local
    /// copy. A nil kind sends nothing: the server has no "unclassify".
    func save(id: UUID, content: String, tags: [String], kind: MemoryKindDTO? = nil) async -> Bool {
        do {
            let updated = try await client.patch(
                id: id,
                MemoryPatchRequest(content: content, tags: tags, kind: kind)
            )
            if let idx = memories.firstIndex(where: { $0.id == id }) {
                memories[idx] = updated
            }
            return true
        } catch {
            actionError = "Couldn't save changes."
            return false
        }
    }

    func loadDetails(for memory: MemoryDTO) async {
        guard provenanceByMemoryID[memory.id] == nil || routesByMemoryID[memory.id] == nil else { return }
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        async let provenance = try? client.provenance(id: memory.id)
        let loadedCatalog: RouterCatalogResponse?
        if let routerClient {
            loadedCatalog = try? await routerClient.catalog()
        } else {
            loadedCatalog = nil
        }
        let loadedProvenance = await provenance
        if let loadedProvenance { provenanceByMemoryID[memory.id] = loadedProvenance }
        guard let loadedCatalog else { return }
        let origin = memory.provenance?.createdBy?.model
        routesByMemoryID[memory.id] = loadedCatalog.models.compactMap { entry in
            guard entry.provider.rawValue != origin?.provider || entry.model != origin?.model else { return nil }
            return RouterModelRouteDTO(
                provider: entry.provider,
                model: entry.model,
                inputPerMillionUsdMicros: entry.inputPerMillionUsdMicros,
                outputPerMillionUsdMicros: entry.outputPerMillionUsdMicros
            )
        }
    }

    func askAnotherModel(about memory: MemoryDTO, route: RouterModelRouteDTO) async -> UUID? {
        guard let conversationsClient else {
            actionError = "Chat is not available."
            return nil
        }
        do {
            let title = "About: \(String(memory.content.prefix(48)))"
            let conversation = try await conversationsClient.create(ConversationCreateRequest(
                title: title,
                pinnedMemoryIDs: [memory.id],
                routeOverride: route
            ))
            return conversation.id
        } catch {
            actionError = "Couldn't start a chat with that model."
            return nil
        }
    }
}
