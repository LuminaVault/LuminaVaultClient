import Foundation
import LuminaVaultShared

@MainActor
@Observable
final class KnowledgeReasoningViewModel {
    enum LoadState {
        case idle
        case loading
        case ready(KnowledgeGraphResponse)
        case unavailable(String)
    }

    private let client: any KnowledgeGraphClientProtocol
    private(set) var graphState: LoadState = .idle
    private(set) var result: ReasoningQueryResponse?
    private(set) var explanation: ConnectionExplanationResponse?
    private(set) var isReasoning = false
    private(set) var errorMessage: String?
    private(set) var selectedNodeIDs: [UUID] = []
    var selectedPathID: UUID?
    var query = ""

    init(client: any KnowledgeGraphClientProtocol) {
        self.client = client
    }

    func load() async {
        graphState = .loading
        do {
            graphState = try .ready(await client.fetchGraph(limit: 200, minimumConfidence: 0.5))
        } catch {
            graphState = .unavailable(error.localizedDescription)
        }
    }

    func loadIfNeeded() async {
        guard case .idle = graphState else { return }
        await load()
    }

    var graph: KnowledgeGraphResponse? {
        guard case let .ready(graph) = graphState else { return nil }
        return graph
    }

    var selectedNodes: [KnowledgeNodeDTO] {
        guard let graph else { return [] }
        let ids = Set(selectedNodeIDs)
        return graph.nodes.filter { ids.contains($0.id) }
    }

    var selectedPath: KnowledgePathDTO? {
        guard let selectedPathID else { return nil }
        return (explanation?.paths ?? result?.paths ?? []).first { $0.id == selectedPathID }
    }

    func selectPath(_ id: UUID?) {
        selectedPathID = selectedPathID == id ? nil : id
    }

    func clearSelection() {
        selectedNodeIDs = []
        explanation = nil
        selectedPathID = nil
    }

    @discardableResult
    func selectNode(_ id: UUID) async -> Bool {
        if selectedNodeIDs.count != 1 || selectedNodeIDs[0] == id {
            selectedNodeIDs = selectedNodeIDs.first == id ? [] : [id]
            explanation = nil
            selectedPathID = nil
            return false
        }
        let from = selectedNodeIDs[0]
        selectedNodeIDs = [from, id]
        await explain(from: from, to: id)
        return explanation != nil
    }

    func reason() async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isReasoning else { return }
        isReasoning = true
        errorMessage = nil
        explanation = nil
        result = nil
        selectedPathID = nil
        defer { isReasoning = false }
        do {
            var streamedAnswer = ""
            for try await event in client.reasonStream(query: value, maxDepth: 4, limit: 200) {
                switch event.type {
                case "context", "suggestions", "result":
                    if let response = event.response {
                        result = response
                        streamedAnswer = response.answer
                    }
                case "token":
                    guard let token = event.message else { continue }
                    streamedAnswer += token
                    let context = result
                    result = ReasoningQueryResponse(
                        answer: streamedAnswer,
                        paths: context?.paths ?? [],
                        evidence: context?.evidence ?? [],
                        confidence: context?.confidence ?? 0,
                        caveats: context?.caveats ?? [],
                        suggestions: context?.suggestions ?? []
                    )
                case "error":
                    throw KnowledgeReasoningStreamError.server(event.message ?? "Reasoning failed")
                default:
                    continue
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func explain(_ edge: KnowledgeEdgeDTO) async {
        selectedNodeIDs = [edge.from, edge.to]
        await explain(from: edge.from, to: edge.to)
    }

    func explain(from: UUID, to: UUID) async {
        isReasoning = true
        errorMessage = nil
        selectedPathID = nil
        defer { isReasoning = false }
        do {
            explanation = try await client.explain(from: from, to: to, maxDepth: 4)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func review(_ edge: KnowledgeEdgeDTO, action: KnowledgeReviewAction) async {
        do {
            let updated = try await client.review(edgeID: edge.id, action: action, note: nil)
            if case let .ready(graph) = graphState {
                graphState = .ready(KnowledgeGraphResponse(
                    nodes: graph.nodes,
                    edges: graph.edges.map { $0.id == updated.id ? updated : $0 },
                    generatedAt: graph.generatedAt
                ))
            }
            guard let current = result else { return }
            result = ReasoningQueryResponse(
                answer: current.answer,
                paths: current.paths,
                evidence: current.evidence,
                confidence: current.confidence,
                caveats: current.caveats,
                suggestions: current.suggestions.filter { $0.id != edge.id }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum KnowledgeReasoningStreamError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case let .server(message): message
        }
    }
}
