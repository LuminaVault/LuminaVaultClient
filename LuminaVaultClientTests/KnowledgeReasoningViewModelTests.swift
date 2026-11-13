// A port of the web app's `reasoning-view-model.test.ts`. Same cases, same
// order; UUIDs stand in for the web's string ids.

import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Synchronization
import Testing

@MainActor
struct KnowledgeReasoningViewModelTests {
    private let f = ReasoningFixture()

    @Test("requests an explanation for two knowledge nodes")
    func explainsTwoNodes() async {
        let client = ReasoningClientStub()
        client.explainReply = { [explanation = f.explanation] _ in explanation }
        let vm = KnowledgeReasoningViewModel(client: client)
        await vm.explainNodes(from: f.firstNode.id, to: f.secondNode.id).value

        #expect(client.explainCalls == [.init(from: f.firstNode.id, to: f.secondNode.id, maxDepth: 4)])
        #expect(vm.explanation == f.explanation)
        #expect(vm.loading == false)
        // The memories behind the explanation's paths light up too.
        #expect(vm.highlightedMemoryIDs == [f.memNode, f.memEdge])
    }

    @Test("streams an answer and highlights its evidence")
    func streamsAnswer() async {
        let client = ReasoningClientStub()
        client.streamEvents = [
            .init(type: "context", response: f.result),
            .init(type: "token", message: "Because "),
            .init(type: "token", message: "of recall."),
        ]
        let vm = KnowledgeReasoningViewModel(client: client)
        vm.query = "  What connects A, B?  "
        await vm.reason()?.value

        #expect(client.streamCalls == [.init(query: "What connects A, B?", maxDepth: 4, limit: 400)])
        #expect(vm.result?.answer == "Because of recall.")
        #expect(vm.highlightedMemoryIDs == [f.memResult, f.memNode, f.memEdge])
    }

    @Test("discarding the answer for a vault change disposes and clears all of it")
    func discardsTheAnswer() async {
        let client = ReasoningClientStub()
        client.streamEvents = [.init(type: "context", response: f.result), .init(type: "token", message: "An answer.")]
        client.explainReply = { [explanation = f.explanation] _ in explanation }
        let vm = KnowledgeReasoningViewModel(client: client)
        vm.query = "What connects A, B?"
        await vm.reason()?.value
        await vm.explainNodes(from: f.firstNode.id, to: f.secondNode.id, subject: "A and B").value
        vm.selectPath(f.path1)
        #expect(vm.result != nil)
        #expect(vm.explanation != nil)
        #expect(vm.explanationSubject == "A and B")
        #expect(vm.selectedPathID == f.path1)

        vm.discardAnswer()
        #expect(vm.result == nil)
        #expect(vm.explanation == nil)
        #expect(vm.explanationSubject == nil)
        #expect(vm.selectedPathID == nil)
        #expect(vm.error == nil)
        #expect(vm.loading == false)
        #expect(vm.reviewing == nil)
        // The question the old answer belonged to is forgotten: prefilling it
        // again no longer counts as "the same question".
        vm.result = f.result
        vm.prefill("What connects A, B?")
        #expect(vm.result == nil)
    }

    @Test("narrows highlights to the selected path")
    func narrowsToPath() {
        let vm = KnowledgeReasoningViewModel(client: ReasoningClientStub())
        vm.result = f.result
        vm.selectPath(f.path1)
        #expect(vm.highlightedMemoryIDs == [f.memResult, f.memNode])
        vm.selectPath(nil)
        #expect(vm.highlightedMemoryIDs.contains(f.memEdge))
    }

    @Test("does not send an empty question")
    func emptyQuestion() async {
        let client = ReasoningClientStub()
        let vm = KnowledgeReasoningViewModel(client: client)
        vm.query = "   "
        await vm.reason()?.value
        #expect(client.streamCalls.isEmpty)
    }

    @Test("reports a stream error event")
    func streamErrorEvent() async {
        let client = ReasoningClientStub()
        client.streamEvents = [.init(type: "error", message: "No knowledge yet")]
        let vm = KnowledgeReasoningViewModel(client: client)
        vm.query = "Why?"
        await vm.reason()?.value
        #expect(vm.error == "No knowledge yet")
        #expect(vm.loading == false)
    }

    @Test("removes a reviewed suggestion")
    func reviewRemovesSuggestion() async {
        let client = ReasoningClientStub()
        let vm = KnowledgeReasoningViewModel(client: client)
        vm.result = f.result
        await vm.review(f.suggestion, action: .confirm)?.value
        #expect(client.reviewCalls == [.init(edgeID: f.suggestion.id, action: .confirm)])
        #expect(vm.result?.suggestions == [])
        #expect(vm.reviewing == nil)
    }

    @Test("abandons an in-flight stream on dispose")
    func disposeAbandonsStream() async throws {
        let client = ReasoningClientStub()
        client.holdStream = true
        let vm = KnowledgeReasoningViewModel(client: client)
        vm.query = "Why?"
        let running = try #require(vm.reason())
        let stream = try await client.waitForStream()
        stream.yield(.init(type: "context", response: f.result))
        try await waitUntil { vm.result != nil }
        vm.dispose()
        #expect(running.isCancelled)
        stream.yield(.init(type: "token", message: "late"))
        stream.finish()
        await running.value
        #expect(vm.result?.answer.isEmpty == true)
        #expect(vm.loading == false)
    }

    @Test("dispose during a review leaves the next review free to start")
    func disposeClearsReviewing() async throws {
        let client = ReasoningClientStub()
        let gate = Gate()
        client.reviewGate = gate
        let vm = KnowledgeReasoningViewModel(client: client)
        vm.result = f.result
        let first = try #require(vm.review(f.suggestion, action: .confirm))
        #expect(vm.reviewing == f.suggestion.id)
        vm.dispose()
        #expect(vm.reviewing == nil)
        await gate.open()
        await first.value
        // The late reply lands nowhere: the reviewing flag stays clear and the
        // suggestion is still there to review again.
        #expect(vm.reviewing == nil)
        #expect(vm.result?.suggestions == [f.suggestion])
        client.reviewGate = nil
        await vm.review(f.suggestion, action: .dismiss)?.value
        #expect(vm.result?.suggestions == [])
    }

    @Test("keeps the answer and its suggestions when a suggestion is explained")
    func explainingASuggestionKeepsTheAnswer() async {
        let client = ReasoningClientStub()
        client.explainReply = { [explanation = f.explanation] _ in explanation }
        let vm = KnowledgeReasoningViewModel(client: client)
        vm.result = f.result
        vm.explanation = ConnectionExplanationResponse(explanation: "Stale.", paths: [], confidence: 0.81)
        let pending = vm.explainNodes(from: f.suggestion.from, to: f.suggestion.to)
        // The stale explanation goes at once; the answer stays.
        #expect(vm.explanation == nil)
        await pending.value
        #expect(vm.result?.suggestions == [f.suggestion])
        #expect(vm.result?.evidence == f.result.evidence)
        #expect(vm.explanation == f.explanation)
    }

    @Test("remembers what an explanation is about until the next question")
    func explanationSubject() async {
        let client = ReasoningClientStub()
        client.explainReply = { [explanation = f.explanation] _ in explanation }
        let vm = KnowledgeReasoningViewModel(client: client)
        await vm.explainNodes(from: UUID(), to: UUID(), subject: "Hermes and Cloudflare").value
        #expect(vm.explanationSubject == "Hermes and Cloudflare")
        vm.query = "Why?"
        await vm.reason()?.value
        #expect(vm.explanationSubject == nil)
        #expect(vm.explanation == nil)
    }

    @Test("drops an older explanation when a newer request starts")
    func newerExplanationWins() async throws {
        let client = ReasoningClientStub()
        let gate = Gate()
        let newer = ConnectionExplanationResponse(explanation: "Newer.", paths: [], confidence: 0.81)
        let older = f.explanation
        client.explainReply = { call in
            if call == 0 {
                await gate.wait()
                return older
            }
            return newer
        }
        let vm = KnowledgeReasoningViewModel(client: client)
        let first = vm.explainNodes(from: UUID(), to: UUID())
        try await waitUntil { client.explainCalls.count == 1 }
        await vm.explainNodes(from: UUID(), to: UUID()).value
        await gate.open()
        await first.value
        #expect(vm.explanation?.explanation == "Newer.")
    }

    // MARK: errors and prefill

    @Test("says what an API failure was, not a generic line")
    func friendlyErrors() async {
        let client = ReasoningClientStub()
        client.streamError = APIError.rateLimited(retryAfter: nil)
        let vm = KnowledgeReasoningViewModel(client: client)
        vm.query = "Why?"
        await vm.reason()?.value
        #expect(vm.error == "You've hit today's limit. Try again later.")

        client.explainReply = { _ in throw APIError.networkFailure(URLError(.notConnectedToInternet)) }
        await vm.explainNodes(from: UUID(), to: UUID()).value
        #expect(vm.error == "Network unavailable.")
    }

    @Test("a prefilled question that differs from the answered one clears the answer")
    func prefillClearsADifferentAnswer() async {
        let client = ReasoningClientStub()
        client.streamEvents = [.init(type: "context", response: f.result.with(answer: "Yes."))]
        let vm = KnowledgeReasoningViewModel(client: client)
        vm.query = "What connects A, B?"
        await vm.reason()?.value
        #expect(vm.result?.answer == "Yes.")

        vm.prefill("What connects A, B?")
        #expect(vm.result?.answer == "Yes.")

        vm.explanation = f.explanation
        vm.prefill("What connects A, B, C?")
        #expect(vm.query == "What connects A, B, C?")
        #expect(vm.result == nil)
        #expect(vm.explanation == nil)
    }

    @Test("VoiceOver hears the work start, then the error or that an answer is ready")
    func progressNotes() {
        typealias Sheet = KnowledgeReasoningSheet
        #expect(Sheet.progressNote(loading: true, error: nil, answered: false) == Sheet.tracingText)
        #expect(Sheet.progressNote(loading: true, error: nil, answered: true) == Sheet.tracingText)
        #expect(Sheet.progressNote(loading: false, error: "Network unavailable.", answered: false) == "Network unavailable.")
        #expect(Sheet.progressNote(loading: false, error: nil, answered: true) == Sheet.answerReadyText)
        #expect(Sheet.progressNote(loading: false, error: nil, answered: false) == nil)
    }
}

// MARK: - Fixture

private nonisolated struct ReasoningFixture: Sendable {
    let memNode = UUID(), memEdge = UUID(), memResult = UUID()
    let path1 = UUID(), path2 = UUID()
    let firstNode: KnowledgeNodeDTO
    let secondNode: KnowledgeNodeDTO
    let edge: KnowledgeEdgeDTO
    let suggestion: KnowledgeEdgeDTO
    let explanation: ConnectionExplanationResponse
    let result: ReasoningQueryResponse

    init() {
        firstNode = KnowledgeNodeDTO(
            id: UUID(), kind: .claim, label: "AI improves recall", confidence: 0.92,
            evidence: [KnowledgeEvidenceDTO(id: UUID(), memoryID: memNode, quote: "node quote")]
        )
        secondNode = KnowledgeNodeDTO(id: UUID(), kind: .event, label: "Retrieval experiment", confidence: 0.84)
        edge = KnowledgeEdgeDTO(
            id: UUID(), from: firstNode.id, to: secondNode.id, predicate: .supports, state: .asserted,
            confidence: 0.81, evidence: [KnowledgeEvidenceDTO(id: UUID(), memoryID: memEdge, quote: "edge quote")]
        )
        suggestion = KnowledgeEdgeDTO(
            id: UUID(), from: firstNode.id, to: secondNode.id, predicate: .supports, state: .suggested,
            confidence: 0.81, evidence: edge.evidence
        )
        explanation = ConnectionExplanationResponse(
            explanation: "The experiment supports the claim.",
            paths: [KnowledgePathDTO(id: path1, nodes: [firstNode, secondNode], edges: [edge], confidence: 0.81)],
            confidence: 0.81
        )
        result = ReasoningQueryResponse(
            answer: "",
            paths: [
                KnowledgePathDTO(id: path1, nodes: [firstNode], edges: [], confidence: 0.8),
                KnowledgePathDTO(id: path2, nodes: [], edges: [edge], confidence: 0.6),
            ],
            evidence: [KnowledgeEvidenceDTO(id: UUID(), memoryID: memResult, quote: "result quote")],
            confidence: 0.7,
            suggestions: [suggestion]
        )
    }
}

private extension ReasoningQueryResponse {
    func with(answer: String) -> ReasoningQueryResponse {
        ReasoningQueryResponse(
            answer: answer, paths: paths, evidence: evidence, confidence: confidence,
            caveats: caveats, suggestions: suggestions
        )
    }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0 ..< 400 where !condition() {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(condition())
}

private actor Gate {
    private var open_ = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if open_ { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        open_ = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// Records every call. A held stream is handed to the test to push events into.
private nonisolated final class ReasoningClientStub: KnowledgeGraphClientProtocol {
    struct StreamCall: Equatable { var query: String; var maxDepth: Int; var limit: Int }
    struct ExplainCall: Equatable { var from: UUID; var to: UUID; var maxDepth: Int }
    struct ReviewCall: Equatable { var edgeID: UUID; var action: KnowledgeReviewAction }

    private struct State {
        var streamEvents: [ReasoningStreamEventDTO] = []
        var streamError: (any Error)?
        var holdStream = false
        var held: AsyncThrowingStream<ReasoningStreamEventDTO, any Error>.Continuation?
        var explainReply: (@Sendable (Int) async throws -> ConnectionExplanationResponse)?
        var streamCalls: [StreamCall] = []
        var explainCalls: [ExplainCall] = []
        var reviewCalls: [ReviewCall] = []
        var reviewGate: Gate?
    }

    private let state = Mutex(State())

    var streamEvents: [ReasoningStreamEventDTO] {
        get { state.withLock { $0.streamEvents } }
        set { state.withLock { $0.streamEvents = newValue } }
    }
    var streamError: (any Error)? {
        get { state.withLock { $0.streamError } }
        set { state.withLock { $0.streamError = newValue } }
    }
    var holdStream: Bool {
        get { state.withLock { $0.holdStream } }
        set { state.withLock { $0.holdStream = newValue } }
    }
    var explainReply: (@Sendable (Int) async throws -> ConnectionExplanationResponse)? {
        get { state.withLock { $0.explainReply } }
        set { state.withLock { $0.explainReply = newValue } }
    }
    var streamCalls: [StreamCall] { state.withLock { $0.streamCalls } }
    var explainCalls: [ExplainCall] { state.withLock { $0.explainCalls } }
    var reviewCalls: [ReviewCall] { state.withLock { $0.reviewCalls } }
    var reviewGate: Gate? {
        get { state.withLock { $0.reviewGate } }
        set { state.withLock { $0.reviewGate = newValue } }
    }

    func waitForStream() async throws -> AsyncThrowingStream<ReasoningStreamEventDTO, any Error>.Continuation {
        for _ in 0 ..< 400 {
            if let held = state.withLock({ $0.held }) { return held }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CancellationError()
    }

    func reason(query _: String, maxDepth _: Int, limit _: Int) async throws -> ReasoningQueryResponse {
        Issue.record("the view model streams; it never asks for a whole answer")
        throw CancellationError()
    }

    func reasonStream(
        query: String, maxDepth: Int, limit: Int
    ) -> AsyncThrowingStream<ReasoningStreamEventDTO, any Error> {
        let (stream, continuation) = AsyncThrowingStream<ReasoningStreamEventDTO, any Error>.makeStream()
        let setup = state.withLock { s in
            s.streamCalls.append(StreamCall(query: query, maxDepth: maxDepth, limit: limit))
            if s.holdStream { s.held = continuation }
            return (s.holdStream, s.streamEvents, s.streamError)
        }
        if !setup.0 {
            for event in setup.1 { continuation.yield(event) }
            continuation.finish(throwing: setup.2)
        }
        return stream
    }

    func explain(from: UUID, to: UUID, maxDepth: Int) async throws -> ConnectionExplanationResponse {
        let (n, reply) = state.withLock { s in
            s.explainCalls.append(ExplainCall(from: from, to: to, maxDepth: maxDepth))
            return (s.explainCalls.count - 1, s.explainReply)
        }
        guard let reply else { throw CancellationError() }
        return try await reply(n)
    }

    func review(edgeID: UUID, action: KnowledgeReviewAction, note _: String?) async throws -> KnowledgeEdgeDTO {
        let gate = state.withLock { s in
            s.reviewCalls.append(ReviewCall(edgeID: edgeID, action: action))
            return s.reviewGate
        }
        if let gate { await gate.wait() }
        return KnowledgeEdgeDTO(
            id: edgeID, from: UUID(), to: UUID(), predicate: .supports,
            state: action == .confirm ? .confirmed : .dismissed, confidence: 0.81
        )
    }
}
