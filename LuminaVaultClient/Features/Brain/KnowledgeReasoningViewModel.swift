// Ask / explain / review over the knowledge graph, for the Brain tab's
// reasoning sheet. A port of the web app's `reasoning-view-model.svelte.ts`.
// Every route is scoped to the active vault by the `X-Vault-ID` header
// `BaseHTTPClient` adds. Requests start only from an explicit call; a newer
// one (or `dispose`) cancels the one in flight, whose late events are dropped.
//
// The view model owns the Tasks it starts (so `dispose` can cancel them) and
// returns them, for tests and for callers that want to wait.

import Foundation
import LuminaVaultShared
import Observation

@MainActor
@Observable
final class KnowledgeReasoningViewModel {
    var query = ""
    /// Settable: a caller starting a fresh explanation clears it.
    var result: ReasoningQueryResponse?
    var explanation: ConnectionExplanationResponse?
    /// What the explanation is about, for its heading ("Hermes and Cloudflare").
    private(set) var explanationSubject: String?
    private(set) var selectedPathID: UUID?
    private(set) var loading = false
    private(set) var error: String?
    /// The suggestion being confirmed or dismissed.
    private(set) var reviewing: UUID?

    /// The question `result` answers.
    private var answered: String?
    private var seq = 0
    /// Bumped by `dispose` only: a review does not abandon the answer it belongs to.
    private var generation = 0
    private var running: Task<Void, Never>?

    private let client: any KnowledgeGraphClientProtocol

    static let maxDepth = 4
    static let limit = 400

    init(client: any KnowledgeGraphClientProtocol) {
        self.client = client
    }

    /// Puts `query` in the question box without asking it. An answer to a
    /// different question no longer applies, so it goes.
    func prefill(_ query: String) {
        if result == nil || query.trimmingCharacters(in: .whitespacesAndNewlines) != answered {
            result = nil
            explanation = nil
            explanationSubject = nil
        }
        self.query = query
    }

    /// Streams an answer to `query`. `nil` when the question is empty.
    @discardableResult
    func reason() -> Task<Void, Never>? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let mine = begin()
        explanation = nil
        explanationSubject = nil
        result = nil
        answered = query
        let stream = client.reasonStream(query: query, maxDepth: Self.maxDepth, limit: Self.limit)
        return start(mine) { [weak self] in
            do {
                for try await event in stream {
                    guard let self, mine == self.seq else { return }
                    try self.consume(event)
                }
            } catch {
                guard let self, mine == self.seq, !error.isBenignCancellation else { return }
                self.error = BrainLoadErrors.friendly(error, fallback: "Reasoning query failed")
            }
        }
    }

    /// Leaves `result` alone: explaining one of its suggested connections must
    /// keep the answer and the suggestions still waiting for review. A caller
    /// starting a fresh explanation clears `result` itself.
    @discardableResult
    func explainNodes(from: UUID, to: UUID, subject: String? = nil) -> Task<Void, Never> {
        let mine = begin()
        explanation = nil
        explanationSubject = subject
        let client = client
        return start(mine) { [weak self] in
            do {
                let value = try await client.explain(from: from, to: to, maxDepth: Self.maxDepth)
                guard let self, mine == self.seq else { return }
                self.explanation = value
            } catch {
                guard let self, mine == self.seq, !error.isBenignCancellation else { return }
                self.error = BrainLoadErrors.friendly(error, fallback: "Connection explanation failed")
            }
        }
    }

    /// Confirms or dismisses a suggested connection. `nil` while another review runs.
    @discardableResult
    func review(_ edge: KnowledgeEdgeDTO, action: KnowledgeReviewAction) -> Task<Void, Never>? {
        guard reviewing == nil else { return nil }
        let generation = generation
        reviewing = edge.id
        error = nil
        let client = client
        return Task { [weak self] in
            do {
                let updated = try await client.review(edgeID: edge.id, action: action, note: nil)
                guard let self, generation == self.generation else { return }
                if let current = self.result {
                    self.result = current.replacing(
                        suggestions: current.suggestions.filter { $0.id != updated.id }
                    )
                }
                self.reviewing = nil
            } catch {
                guard let self, generation == self.generation else { return }
                self.error = BrainLoadErrors.friendly(error, fallback: "Connection review failed")
                self.reviewing = nil
            }
        }
    }

    func selectPath(_ id: UUID?) {
        selectedPathID = id
    }

    /// The memories behind what is on show: the answer's evidence, plus the
    /// evidence on the nodes and edges of its paths (or of the explanation's),
    /// narrowed to the selected path when there is one.
    var highlightedMemoryIDs: Set<UUID> {
        var ids = Set(result?.evidence.map(\.memoryID) ?? [])
        for path in visiblePaths {
            for node in path.nodes { ids.formUnion(node.evidence.map(\.memoryID)) }
            for edge in path.edges { ids.formUnion(edge.evidence.map(\.memoryID)) }
        }
        return ids
    }

    /// Abandons whatever is in flight; nothing it sends afterwards lands.
    func dispose() {
        seq += 1
        generation += 1
        running?.cancel()
        running = nil
        loading = false
        // The review in flight can no longer clear it (its generation is
        // stale), and a kept view model would leave Confirm and Dismiss off.
        reviewing = nil
    }

    /// The answer was about a vault that is no longer the active one: abandons
    /// what is in flight and clears what is on show. The question stays.
    func discardAnswer() {
        dispose()
        result = nil
        explanation = nil
        explanationSubject = nil
        selectedPathID = nil
        error = nil
        answered = nil
    }

    // MARK: private

    private var visiblePaths: [KnowledgePathDTO] {
        let paths = explanation?.paths ?? result?.paths ?? []
        guard let selectedPathID else { return paths }
        return paths.filter { $0.id == selectedPathID }
    }

    private func begin() -> Int {
        running?.cancel()
        running = nil
        loading = true
        error = nil
        selectedPathID = nil
        seq += 1
        return seq
    }

    private func start(_ mine: Int, _ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let task = Task { [weak self] in
            await work()
            guard let self, mine == self.seq else { return }
            self.loading = false
            self.running = nil
        }
        running = task
        return task
    }

    private func consume(_ event: ReasoningStreamEventDTO) throws {
        switch event.type {
        case "context", "suggestions":
            if let response = event.response { result = response }
        case "token":
            if let current = result {
                result = current.replacing(answer: current.answer + (event.message ?? ""))
            }
        case "error":
            throw KnowledgeReasoningStreamError.server(event.message ?? "Reasoning stream failed")
        default:
            break
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

private extension ReasoningQueryResponse {
    func replacing(answer: String? = nil, suggestions: [KnowledgeEdgeDTO]? = nil) -> ReasoningQueryResponse {
        ReasoningQueryResponse(
            answer: answer ?? self.answer,
            paths: paths,
            evidence: evidence,
            confidence: confidence,
            caveats: caveats,
            suggestions: suggestions ?? self.suggestions
        )
    }
}
