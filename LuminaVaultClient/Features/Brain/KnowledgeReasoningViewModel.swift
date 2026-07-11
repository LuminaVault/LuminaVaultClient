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

    func reason() async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isReasoning else { return }
        isReasoning = true
        errorMessage = nil
        explanation = nil
        result = nil
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
        isReasoning = true
        errorMessage = nil
        defer { isReasoning = false }
        do {
            explanation = try await client.explain(from: edge.from, to: edge.to, maxDepth: 4)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func review(_ edge: KnowledgeEdgeDTO, action: KnowledgeReviewAction) async {
        do {
            _ = try await client.review(edgeID: edge.id, action: action, note: nil)
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
