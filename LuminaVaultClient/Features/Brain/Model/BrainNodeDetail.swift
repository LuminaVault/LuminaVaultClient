// The detail sheet behind the tray's Open (and a double tap on a point). A port
// of the web app's `node-detail.svelte.ts`: a memory loads its body from
// `GET /v1/memory/{id}` in the vault it lives in; a note shows what the graph
// already knows. A body that lands after another point was opened (or after
// `dispose`) is dropped.

import Foundation
import LuminaVaultShared
import Observation

/// Error copy shared by the detail sheet and the reasoning sheet. The same
/// sentences as the web's `friendlyLoadError`.
nonisolated enum BrainLoadErrors {
    static func friendly(_ error: any Error, fallback: String = "Couldn't load.") -> String {
        if let api = error as? APIError {
            if case .rateLimited = api { return "You've hit today's limit. Try again later." }
            switch api {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default:
                if api.httpStatusCode == 429 { return "You've hit today's limit. Try again later." }
                return api.userFacingMessage
            }
        }
        let text = (error as? LocalizedError)?.errorDescription ?? ""
        return text.isEmpty ? fallback : text
    }
}

@MainActor
@Observable
final class BrainNodeDetail {
    enum MemoryState: Equatable {
        case loading
        case loaded(MemoryDTO)
        case failed(String)
    }

    var isOpen = false
    private(set) var node: BrainGraphNodeDTO?
    /// `nil` for anything but a memory.
    private(set) var memory: MemoryState?

    private let client: (any MemoryClientProtocol)?
    private var seq = 0
    private var task: Task<Void, Never>?

    init(client: (any MemoryClientProtocol)?) {
        self.client = client
    }

    /// Opens `node`. Returns the load, for tests; `nil` when nothing loads.
    @discardableResult
    func show(_ node: BrainGraphNodeDTO) -> Task<Void, Never>? {
        abandon()
        let mine = seq
        self.node = node
        isOpen = true
        guard node.kind == .memory else {
            memory = nil
            return nil
        }
        guard let client, let id = UUID(uuidString: node.id) else {
            memory = .failed("This memory cannot be opened here.")
            return nil
        }
        memory = .loading
        // The graph spans every vault and the server looks a memory up in the
        // vault the request names, so it names the memory's own.
        let vault = node.vaultID
        let load = Task { [weak self] in
            do {
                let value = try await client.get(id: id, vaultID: vault)
                guard let self, mine == self.seq else { return }
                self.memory = .loaded(value)
            } catch {
                guard let self, mine == self.seq else { return }
                self.memory = .failed(BrainLoadErrors.friendly(error))
            }
        }
        task = load
        return load
    }

    func dispose() {
        abandon()
        isOpen = false
    }

    private func abandon() {
        seq += 1
        task?.cancel()
        task = nil
    }
}
