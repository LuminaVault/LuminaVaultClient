import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

@MainActor
struct KnowledgeReasoningViewModelTests {
    @Test("Reasoning result and review state flow through the view model")
    func reasoningAndReview() async throws {
        let fixture = KnowledgeFixture()
        let client = KnowledgeGraphClientMock(fixture: fixture)
        let viewModel = KnowledgeReasoningViewModel(client: client)
        viewModel.query = "What contradicts my Atlas plan?"

        await viewModel.reason()

        #expect(viewModel.result?.answer == "Atlas has two positions.")
        #expect(viewModel.result?.suggestions.count == 1)
        let edge = try #require(viewModel.result?.suggestions.first)

        await viewModel.explain(edge)
        #expect(viewModel.explanation?.explanation == "The claims use opposing polarity.")

        await viewModel.review(edge, action: .confirm)
        #expect(viewModel.result?.suggestions.isEmpty == true)
    }

    @Test("Selecting two graph nodes explains the connection")
    func nodeSelectionExplainsConnection() async {
        let fixture = KnowledgeFixture()
        let viewModel = KnowledgeReasoningViewModel(client: KnowledgeGraphClientMock(fixture: fixture))
        await viewModel.load()

        let firstExplained = await viewModel.selectNode(fixture.from.id)
        let secondExplained = await viewModel.selectNode(fixture.to.id)

        #expect(firstExplained == false)
        #expect(secondExplained)
        #expect(viewModel.selectedNodeIDs == [fixture.from.id, fixture.to.id])
        #expect(viewModel.explanation?.confidence == 0.6)

        viewModel.selectedPathID = UUID()
        viewModel.clearSelection()
        #expect(viewModel.selectedNodeIDs.isEmpty)
        #expect(viewModel.selectedPathID == nil)
    }

    @Test("Knowledge projection preserves IDs, confidence, and active predicates")
    func graphProjection() {
        let fixture = KnowledgeFixture()
        let dismissed = KnowledgeEdgeDTO(
            id: UUID(), from: fixture.to.id, to: fixture.from.id,
            predicate: .relatedTo, state: .dismissed, confidence: 1
        )
        let graph = KnowledgeGraphResponse(
            nodes: [fixture.from, fixture.to],
            edges: [fixture.edge, dismissed],
            generatedAt: Date(timeIntervalSince1970: 1)
        )

        let projected = KnowledgeGraphProjection.make(
            graph: graph,
            selectedNodeIDs: [fixture.from.id]
        )

        #expect(projected.nodes.map(\.id) == [fixture.from.id, fixture.to.id])
        #expect(projected.nodes.first?.score == 100)
        #expect(projected.nodes.first?.activity == 1)
        #expect(projected.edges.count == 1)
        #expect(projected.edges.first?.kind == .tag)
        #expect(projected.edges.first?.tag == "contradicts")
    }
}

private struct KnowledgeFixture: Sendable {
    let evidence: KnowledgeEvidenceDTO
    let from: KnowledgeNodeDTO
    let to: KnowledgeNodeDTO
    let edge: KnowledgeEdgeDTO

    init() {
        evidence = KnowledgeEvidenceDTO(id: UUID(), memoryID: UUID(), quote: "Atlas is ready. Atlas is not ready.")
        from = KnowledgeNodeDTO(id: UUID(), kind: .claim, label: "Atlas is ready", confidence: 1)
        to = KnowledgeNodeDTO(id: UUID(), kind: .claim, label: "Atlas is not ready", confidence: 1)
        edge = KnowledgeEdgeDTO(
            id: UUID(), from: from.id, to: to.id, predicate: .contradicts,
            state: .suggested, confidence: 0.6, evidence: [evidence]
        )
    }
}

private actor KnowledgeGraphClientMock: KnowledgeGraphClientProtocol {
    let fixture: KnowledgeFixture
    init(fixture: KnowledgeFixture) {
        self.fixture = fixture
    }

    func fetchGraph(limit _: Int, minimumConfidence _: Double) async throws -> KnowledgeGraphResponse {
        KnowledgeGraphResponse(nodes: [fixture.from, fixture.to], edges: [fixture.edge], generatedAt: Date())
    }

    func reason(query _: String, maxDepth _: Int, limit _: Int) async throws -> ReasoningQueryResponse {
        ReasoningQueryResponse(
            answer: "Atlas has two positions.", paths: [], evidence: [fixture.evidence],
            confidence: 0.6, suggestions: [fixture.edge]
        )
    }

    nonisolated func reasonStream(
        query _: String,
        maxDepth _: Int,
        limit _: Int
    ) -> AsyncThrowingStream<ReasoningStreamEventDTO, any Error> {
        let fixture = fixture
        return AsyncThrowingStream { continuation in
            continuation.yield(ReasoningStreamEventDTO(
                type: "suggestions",
                response: ReasoningQueryResponse(
                    answer: "Atlas has two positions.", paths: [], evidence: [fixture.evidence],
                    confidence: 0.6, suggestions: [fixture.edge]
                )
            ))
            continuation.finish()
        }
    }

    func explain(from _: UUID, to _: UUID, maxDepth _: Int) async throws -> ConnectionExplanationResponse {
        ConnectionExplanationResponse(explanation: "The claims use opposing polarity.", paths: [], confidence: 0.6)
    }

    func review(edgeID: UUID, action _: KnowledgeReviewAction, note _: String?) async throws -> KnowledgeEdgeDTO {
        KnowledgeEdgeDTO(
            id: edgeID, from: fixture.edge.from, to: fixture.edge.to,
            predicate: fixture.edge.predicate, state: .confirmed,
            confidence: fixture.edge.confidence, evidence: fixture.edge.evidence
        )
    }
}
