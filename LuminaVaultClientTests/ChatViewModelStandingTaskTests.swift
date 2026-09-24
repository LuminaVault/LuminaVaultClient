// LuminaVaultClient/LuminaVaultClientTests/ChatViewModelStandingTaskTests.swift
//
// Muse Stage C ("Standing-task card") — confirming a job proposal creates the
// job (POST /v1/jobs) and, only once that succeeds, Hermie says so in the
// transcript with a "Standing task" caption. A failed create posts nothing.
//
// Async on purpose: synchronous @MainActor XCTest methods crash this host.

@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class ChatViewModelStandingTaskTests: XCTestCase {
    private func makeViewModel(jobs: StubJobsClient) -> ChatViewModel {
        ChatViewModel(
            conversationsClient: InertConversations(),
            chatClient: InertChat(),
            memoryClient: InertMemory(),
            jobsClient: jobs
        )
    }

    private let proposal = JobProposalDTO(
        isJob: true,
        title: "Weather watch",
        cron: "0 7 * * *",
        scheduleHuman: "Every day at 7:00",
        domain: "life",
        spec: "Check the weather each morning; alert when there are 5 consecutive dry days."
    )

    func testConfirmAppendsCaptionedAgentMessageAfterCreate() async {
        let jobs = StubJobsClient(result: .success(()))
        let vm = makeViewModel(jobs: jobs)
        vm.jobProposal = proposal

        await vm.createProposedJob()

        XCTAssertNil(vm.jobProposal)
        let requests = await jobs.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.title, "Weather watch")
        XCTAssertEqual(requests.first?.cron, "0 7 * * *")

        guard let last = vm.messages.last else { return XCTFail("no confirmation appended") }
        XCTAssertEqual(last.role, .assistant)
        XCTAssertEqual(
            last.content,
            "Got it — I'll watch weather watch and ping you when there are 5 consecutive dry days."
        )
        XCTAssertEqual(last.origin, .proactive)
        XCTAssertEqual(last.proactiveCaption, "Standing task")
    }

    func testFailedCreateAppendsNothing() async {
        let jobs = StubJobsClient(result: .failure(APIError.unauthorized))
        let vm = makeViewModel(jobs: jobs)
        vm.jobProposal = proposal

        await vm.createProposedJob()

        XCTAssertNil(vm.jobProposal)
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertEqual(vm.activeToast?.kind, .warning)
    }

    func testIncompleteProposalIsDroppedWithoutCalling() async {
        let jobs = StubJobsClient(result: .success(()))
        let vm = makeViewModel(jobs: jobs)
        vm.jobProposal = JobProposalDTO(isJob: true, title: "No schedule", cron: nil, spec: "x")

        await vm.createProposedJob()

        XCTAssertNil(vm.jobProposal)
        let requests = await jobs.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(vm.messages.isEmpty)
    }
}

// MARK: - Stubs

private actor StubJobsClient: JobsClientProtocol {
    private let result: Result<Void, Error>
    private(set) var requests: [JobCreateRequest] = []

    init(result: Result<Void, Error>) { self.result = result }

    func detect(text _: String) async throws -> JobProposalDTO { JobProposalDTO(isJob: false) }

    func create(_ request: JobCreateRequest) async throws -> LuminaVaultShared.SkillDTO {
        requests.append(request)
        try result.get()
        return SkillDTO(
            id: "job-weather-watch", source: .vault, name: "job-weather-watch", title: request.title,
            descriptionText: "", capability: .medium, enabled: true, bodyExcerpt: ""
        )
    }
}

private struct InertConversations: ConversationsClientProtocol {
    func create(_: ConversationCreateRequest) async throws -> ConversationDTO { throw APIError.unauthorized }
    func list() async throws -> ConversationListResponse { ConversationListResponse(conversations: []) }
    func get(_: UUID) async throws -> ConversationDetailResponse { throw APIError.unauthorized }
    func delete(_: UUID) async throws {}
    func streamReply(
        conversationID _: UUID,
        request _: MessageStreamRequest
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct InertChat: ChatClientProtocol {
    func complete(_: ChatRequest) async throws -> ChatResponse { throw APIError.unauthorized }
}

private struct InertMemory: MemoryClientProtocol {
    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse { throw APIError.unauthorized }
    func get(id _: UUID) async throws -> MemoryDTO { throw APIError.unauthorized }
    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO { throw APIError.unauthorized }
    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse { throw APIError.unauthorized }
    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse { throw APIError.unauthorized }
    func delete(id _: UUID) async throws { throw APIError.unauthorized }
}
