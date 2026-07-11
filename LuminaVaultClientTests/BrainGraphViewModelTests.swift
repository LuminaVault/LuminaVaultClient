// LuminaVaultClient/LuminaVaultClientTests/BrainGraphViewModelTests.swift
// HER-235 — contract tests for BrainGraphViewModel.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class BrainGraphViewModelTests: XCTestCase {
    var client: MockMemoryGraphClient!
    var sut: BrainGraphViewModel!

    override func setUp() async throws {
        try await super.setUp()
        client = MockMemoryGraphClient()
        sut = BrainGraphViewModel(client: client)
    }

    func testInitialStateIsIdle() {
        if case .idle = sut.state {} else {
            XCTFail("expected idle, got \(sut.state)")
        }
        XCTAssertNil(sut.selectedNodeID)
    }

    func testLoadHappyPath() async {
        let stub = MemoryGraphResponse.stub(nodeCount: 3)
        client.fetchResult = .success(stub)
        await sut.load()
        guard case .loaded(let graph) = sut.state else {
            return XCTFail("expected loaded, got \(sut.state)")
        }
        XCTAssertEqual(graph.nodes.count, 3)
        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertEqual(client.fetchCallCount, 1)
    }

    func testLoadEmptyResponse() async {
        client.fetchResult = .success(.empty)
        await sut.load()
        guard case .loaded(let graph) = sut.state else {
            return XCTFail("expected loaded, got \(sut.state)")
        }
        XCTAssertTrue(graph.nodes.isEmpty)
        XCTAssertTrue(graph.edges.isEmpty)
    }

    func testLoadFailureAdvancesToFailed() async {
        client.fetchResult = .failure(APIError.unauthorized)
        await sut.load()
        if case .failed = sut.state {} else {
            XCTFail("expected failed, got \(sut.state)")
        }
    }

    func testLoadResetsSelection() async {
        // Selection from a previous run must not survive a re-fetch — the
        // new top-N may not contain the previously-selected memory id.
        sut.selectedNodeID = UUID()
        client.fetchResult = .success(.stub(nodeCount: 2))
        await sut.load()
        XCTAssertNil(sut.selectedNodeID)
    }

    func testNodeLookup() async {
        let stub = MemoryGraphResponse.stub(nodeCount: 3, withEdge: false)
        client.fetchResult = .success(stub)
        await sut.load()
        let firstID = stub.nodes[1].id
        let found = sut.node(for: firstID)
        XCTAssertEqual(found?.id, firstID)
        XCTAssertNil(sut.node(for: UUID()))
    }

    func testLoadForwardsTuningParams() async {
        await sut.load(
            limit: 200,
            similarityThreshold: 0.5,
            maxEdgesPerNode: 4,
            includeWikiPages: false,
            kinds: [.tag, .semantic]
        )
        XCTAssertEqual(client.lastLimit, 200)
        XCTAssertEqual(client.lastSimilarity, 0.5)
        XCTAssertEqual(client.lastMaxEdges, 4)
        XCTAssertEqual(client.lastIncludeWikiPages, false)
        XCTAssertEqual(client.lastKinds, [.tag, .semantic])
    }

    func testGraphEndpointIncludesServerSideFilterParams() {
        let endpoint = MemoryGraphEndpoints.Graph(
            limit: 200,
            similarityThreshold: 0.5,
            maxEdgesPerNode: 4,
            includeWikiPages: false,
            kinds: [.tag, .semantic]
        )
        let components = URLComponents(string: "https://example.test\(endpoint.path)")
        let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components?.path, "/v1/memory/graph")
        XCTAssertEqual(items["limit"] ?? nil, "200")
        XCTAssertEqual(items["similarityThreshold"] ?? nil, "0.5")
        XCTAssertEqual(items["maxEdgesPerNode"] ?? nil, "4")
        XCTAssertEqual(items["includeWikiPages"] ?? nil, "false")
        XCTAssertEqual(items["kinds"] ?? nil, "tag,semantic")
    }
}
