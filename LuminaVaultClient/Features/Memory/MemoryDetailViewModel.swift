// LuminaVaultClient/LuminaVaultClient/Features/Memory/MemoryDetailViewModel.swift
//
// One memory, opened by id: from a `luminavault://memory/<id>` link, a recap
// highlight, or a "Connects to" row. Everything else that shows a memory
// already holds the DTO; this is the screen for when all you have is the id.

import Foundation
import LuminaVaultShared
import Observation

@MainActor
@Observable
final class MemoryDetailViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded(MemoryDTO)
        case failed(String)
    }

    enum RelatedState: Equatable {
        case loading
        case loaded([RelatedMemoryDTO])
        /// Hidden rather than shown as an error: what a memory connects to
        /// is a bonus on this screen, not the reason it was opened.
        case failed
    }

    static let relatedLimit = 5

    let memoryID: UUID
    private(set) var state: LoadState = .loading
    private(set) var related: RelatedState = .loading
    private(set) var provenance: MemoryProvenanceResponse?
    /// Provenance is best-effort; once it has failed the section goes away
    /// instead of spinning forever.
    private(set) var provenanceFailed = false
    private(set) var spaces: [SpaceDTO] = []
    private(set) var isDeleting = false
    var actionError: String?

    private let client: any MemoryClientProtocol
    private let spacesClient: (any SpacesClientProtocol)?

    init(
        memoryID: UUID,
        client: any MemoryClientProtocol,
        spacesClient: (any SpacesClientProtocol)? = nil
    ) {
        self.memoryID = memoryID
        self.client = client
        self.spacesClient = spacesClient
    }

    var memory: MemoryDTO? {
        if case let .loaded(memory) = state { return memory }
        return nil
    }

    func spaceName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return spaces.first { $0.id == id }?.name
    }

    /// The memory, then what it connects to, its source and the Space names,
    /// side by side. Only the memory itself decides whether the screen loads.
    func load() async {
        if memory == nil { state = .loading }
        async let relatedLoad: Void = loadRelated()
        async let provenanceLoad: Void = loadProvenance()
        async let spacesLoad: Void = loadSpaces()
        do {
            state = .loaded(try await client.get(id: memoryID))
        } catch {
            state = .failed(Self.message(for: error))
        }
        _ = await (relatedLoad, provenanceLoad, spacesLoad)
    }

    /// After an edit: the content, kind or Space may have changed. Related
    /// memories are by embedding and the server re-embeds asynchronously, so
    /// they are left alone rather than refetched to the same answer.
    func reload() async {
        do {
            state = .loaded(try await client.get(id: memoryID))
        } catch {
            actionError = "Couldn't refresh this memory."
        }
    }

    /// Returns whether the memory is gone, so the screen can close itself.
    func delete() async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await client.delete(id: memoryID)
            return true
        } catch {
            actionError = "Couldn't delete this memory."
            return false
        }
    }

    /// An editor for the same memory, wired to the same clients. The editor
    /// is the browser's; it only needs the Space list, not a page of memories.
    func makeEditor() -> MemoryBrowserViewModel {
        MemoryBrowserViewModel(client: client, spacesClient: spacesClient)
    }

    private func loadRelated() async {
        do {
            let response = try await client.related(id: memoryID, limit: Self.relatedLimit)
            related = .loaded(response.items.filter { $0.id != memoryID })
        } catch {
            related = .failed
        }
    }

    private func loadProvenance() async {
        do {
            provenance = try await client.provenance(id: memoryID)
        } catch {
            provenanceFailed = true
        }
    }

    private func loadSpaces() async {
        guard spaces.isEmpty, let spacesClient else { return }
        spaces = (try? await spacesClient.list()) ?? []
    }

    private static func message(for error: Error) -> String {
        if case APIError.httpError(statusCode: 404, _) = error { return "This memory no longer exists." }
        return "Couldn't load this memory."
    }
}
