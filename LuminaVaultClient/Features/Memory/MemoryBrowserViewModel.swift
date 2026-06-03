// LuminaVaultClient/LuminaVaultClient/Features/Memory/MemoryBrowserViewModel.swift
//
// Phase 2 — direct memory management. Lists the tenant's memories
// (paged), runs semantic search, and supports edit (content/tags) + delete
// over the existing /v1/memory CRUD endpoints.

import Foundation
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

    init(client: any MemoryClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        offset = 0
        isSearching = false
        actionError = nil
        do {
            let response = try await client.list(limit: pageSize, offset: 0)
            memories = response.memories
            offset = response.memories.count
            canLoadMore = response.memories.count == pageSize
            state = .ready
        } catch {
            state = .failed("Couldn't load your memories.")
        }
    }

    func loadMore() async {
        guard canLoadMore, !isSearching, state == .ready else { return }
        do {
            let response = try await client.list(limit: pageSize, offset: offset)
            memories.append(contentsOf: response.memories)
            offset += response.memories.count
            canLoadMore = response.memories.count == pageSize
        } catch {
            actionError = "Couldn't load more."
        }
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

    func delete(_ memory: MemoryDTO) async {
        do {
            try await client.delete(id: memory.id)
            memories.removeAll { $0.id == memory.id }
        } catch {
            actionError = "Couldn't delete that memory."
        }
    }

    /// Saves an edited memory (content + tags) and replaces the local copy.
    func save(id: UUID, content: String, tags: [String]) async -> Bool {
        do {
            let updated = try await client.patch(
                id: id,
                MemoryPatchRequest(content: content, tags: tags)
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
}
