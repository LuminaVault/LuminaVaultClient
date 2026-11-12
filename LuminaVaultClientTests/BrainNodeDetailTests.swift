// A port of the web app's `node-detail.test.ts`. The header on the wire is
// tested in `MemoryHTTPClientTests` (it shares `MockURLProtocol`).

import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Synchronization
import Testing

@MainActor
struct BrainNodeDetailTests {
    private static let memoryID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000004")!
    private let memory = BrainGraphNodeDTO(id: memoryID.uuidString, kind: .memory, label: "Migration retro", weight: 1)
    private let note = BrainGraphNodeDTO(
        id: "AAAAAAAA-0000-4000-8000-000000000001", kind: .note, label: "Migration retro", weight: 1
    )

    @Test("loads a memory by its id as given")
    func loadsMemory() async {
        let client = DetailMemoryClient()
        let detail = BrainNodeDetail(client: client)
        await detail.show(memory)?.value
        #expect(detail.isOpen)
        #expect(client.calls.map(\.id) == [Self.memoryID])
        #expect(detail.memory == .loaded(DetailMemoryClient.body(Self.memoryID, "Body")))
    }

    @Test("opens a note without asking the server")
    func opensNote() async {
        let client = DetailMemoryClient()
        let detail = BrainNodeDetail(client: client)
        await detail.show(note)?.value
        #expect(detail.isOpen)
        #expect(detail.node == note)
        #expect(detail.memory == nil)
        #expect(client.calls.isEmpty)
    }

    @Test("drops a memory that lands after another point was opened")
    func dropsLateMemory() async throws {
        let client = DetailMemoryClient()
        client.hold = true
        let detail = BrainNodeDetail(client: client)
        let first = detail.show(memory)
        for _ in 0 ..< 400 where client.calls.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        await detail.show(note)?.value
        client.release()
        await first?.value
        #expect(detail.node == note)
        #expect(detail.memory == nil)
    }

    @Test("asks for a memory in the vault it lives in")
    func namesTheMemorysVault() async {
        let vault = UUID()
        let client = DetailMemoryClient()
        let detail = BrainNodeDetail(client: client)
        await detail.show(BrainGraphNodeDTO(
            id: memory.id, kind: .memory, label: memory.label, vaultID: vault, weight: 1
        ))?.value
        #expect(client.calls.map(\.vaultID) == [vault])
    }

    @Test("leaves the vault to the client when the point has none")
    func noVault() async {
        let client = DetailMemoryClient()
        let detail = BrainNodeDetail(client: client)
        await detail.show(memory)?.value
        #expect(client.calls.map(\.vaultID) == [nil])
    }

    @Test("a failure says what went wrong")
    func failure() async {
        let client = DetailMemoryClient()
        client.error = APIError.networkFailure(URLError(.notConnectedToInternet))
        let detail = BrainNodeDetail(client: client)
        await detail.show(memory)?.value
        #expect(detail.memory == .failed("Network unavailable."))
    }

    @Test("dispose closes it and drops what is in flight")
    func dispose() async throws {
        let client = DetailMemoryClient()
        client.hold = true
        let detail = BrainNodeDetail(client: client)
        let running = detail.show(memory)
        for _ in 0 ..< 400 where client.calls.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        detail.dispose()
        #expect(detail.isOpen == false)
        client.release()
        await running?.value
        #expect(detail.memory == .loading)
    }

    @Test("Get names the vault in X-Vault-ID, over the active one")
    func endpointHeader() {
        let vault = UUID()
        #expect(MemoryEndpoints.Get(id: Self.memoryID, vaultID: vault).additionalHeaders == ["X-Vault-ID": vault.uuidString])
        #expect(MemoryEndpoints.Get(id: Self.memoryID).additionalHeaders.isEmpty)
    }
}

/// Answers `get` with a fixed body, or waits until released.
private nonisolated final class DetailMemoryClient: MemoryClientProtocol {
    struct Call: Equatable { var id: UUID; var vaultID: UUID? }
    private struct State {
        var calls: [Call] = []
        var hold = false
        var error: (any Error)?
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    static func body(_ id: UUID, _ content: String) -> MemoryDTO {
        MemoryDTO(id: id, content: content, tags: [], reviewState: "approved")
    }

    var calls: [Call] { state.withLock { $0.calls } }
    var hold: Bool {
        get { state.withLock { $0.hold } }
        set { state.withLock { $0.hold = newValue } }
    }
    var error: (any Error)? {
        get { state.withLock { $0.error } }
        set { state.withLock { $0.error = newValue } }
    }

    func release() {
        let waiters = state.withLock { s in
            s.hold = false
            defer { s.waiters = [] }
            return s.waiters
        }
        waiters.forEach { $0.resume() }
    }

    func get(id: UUID) async throws -> MemoryDTO {
        try await get(id: id, vaultID: nil)
    }

    func get(id: UUID, vaultID: UUID?) async throws -> MemoryDTO {
        let held = state.withLock { s in
            s.calls.append(Call(id: id, vaultID: vaultID))
            return s.hold
        }
        if held {
            await withCheckedContinuation { c in
                let resumeNow = state.withLock { s in
                    if s.hold { s.waiters.append(c); return false }
                    return true
                }
                if resumeNow { c.resume() }
            }
        }
        if let error = state.withLock({ $0.error }) { throw error }
        return Self.body(id, held ? "Late" : "Body")
    }

    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse { throw APIError.unauthorized }
    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO { throw APIError.unauthorized }
    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse { throw APIError.unauthorized }
    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse { throw APIError.unauthorized }
    func delete(id _: UUID) async throws { throw APIError.unauthorized }
}
