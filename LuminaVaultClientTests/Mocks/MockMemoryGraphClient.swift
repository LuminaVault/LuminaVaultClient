// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockMemoryGraphClient.swift
// HER-235 — scripted MemoryGraphClientProtocol fake.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

final class MockMemoryGraphClient: MemoryGraphClientProtocol, @unchecked Sendable {
    var fetchResult: Result<MemoryGraphResponse, Error> = .success(.empty)
    private(set) var fetchCallCount: Int = 0
    private(set) var lastLimit: Int?
    private(set) var lastSimilarity: Double?
    private(set) var lastMaxEdges: Int?
    private(set) var lastIncludeWikiPages: Bool?
    private(set) var lastKinds: [MemoryEdgeKindDTO]?

    func fetchGraph(
        limit: Int?,
        similarityThreshold: Double?,
        maxEdgesPerNode: Int?,
        includeWikiPages: Bool?,
        kinds: [MemoryEdgeKindDTO]?,
    ) async throws -> MemoryGraphResponse {
        fetchCallCount += 1
        lastLimit = limit
        lastSimilarity = similarityThreshold
        lastMaxEdges = maxEdgesPerNode
        lastIncludeWikiPages = includeWikiPages
        lastKinds = kinds
        return try fetchResult.get()
    }
}

extension MemoryGraphResponse {
    static let empty = MemoryGraphResponse(nodes: [], edges: [], generatedAt: Date(timeIntervalSince1970: 0))

    static func stub(nodeCount: Int = 3, withEdge: Bool = true) -> MemoryGraphResponse {
        let ids = (0..<nodeCount).map { _ in UUID() }
        let nodes = ids.enumerated().map { idx, id in
            MemoryGraphNodeDTO(
                id: id,
                title: "Node \(idx)",
                tags: ["shared"],
                createdAt: Date(timeIntervalSince1970: TimeInterval(idx)),
                score: Double(idx) * 0.5,
            )
        }
        let edges: [MemoryGraphEdgeDTO]
        if withEdge, ids.count >= 2 {
            edges = [
                MemoryGraphEdgeDTO(
                    from: ids[0], to: ids[1],
                    kind: .tag, tag: "shared", similarity: nil, weight: 1.0,
                ),
            ]
        } else {
            edges = []
        }
        return MemoryGraphResponse(nodes: nodes, edges: edges, generatedAt: Date(timeIntervalSince1970: 0))
    }
}
