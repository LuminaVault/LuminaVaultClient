// Scripted BrainGraphClientProtocol fake. Records every request and answers
// from a queue of results; the last queued result repeats once the queue is
// down to one.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

actor MockBrainGraphClient: BrainGraphClientProtocol {
    private var results: [Result<BrainGraphResponse, Error>]
    private(set) var requests: [BrainGraphRequest] = []

    init(results: [Result<BrainGraphResponse, Error>] = []) {
        self.results = results
    }

    var callCount: Int { requests.count }
    var lastRequest: BrainGraphRequest? { requests.last }

    func enqueue(_ result: Result<BrainGraphResponse, Error>) { results.append(result) }

    func fetchGraph(_ request: BrainGraphRequest) async throws -> BrainGraphResponse {
        requests.append(request)
        guard let next = results.first else {
            throw MockBrainGraphError.noResultQueued
        }
        if results.count > 1 { results.removeFirst() }
        return try next.get()
    }
}

enum MockBrainGraphError: Error { case noResultQueued }
