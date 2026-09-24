// LuminaVaultClient/LuminaVaultClientTests/ProactiveCaptionTests.swift
//
// Muse Stage C — the caption above a message Hermie sent unprompted, the
// confirmation she posts after a standing task is created, and the transcript
// plumbing that carries `origin` / `sourceLabel` from the wire (and through
// the on-device snapshot) to the bubble.
//
// Async on purpose: synchronous @MainActor XCTest methods crash this host
// ("pointer being freed was not allocated").

@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class ProactiveCaptionTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    /// 2026-09-23 07:00:00 UTC.
    private let sevenAM = Date(timeIntervalSince1970: 1_790_146_800)

    // MARK: - Mapping

    func testRepliesHaveNoCaption() async {
        XCTAssertNil(ProactiveCaption.text(origin: .reply, sourceLabel: nil, createdAt: sevenAM))
        // A label on a reply is ignored — origin decides.
        XCTAssertNil(ProactiveCaption.text(origin: .reply, sourceLabel: "daily-brief", createdAt: sevenAM))
    }

    func testBriefingShowsTwentyFourHourTime() async {
        XCTAssertEqual(
            ProactiveCaption.text(origin: .proactive, sourceLabel: "daily-brief", createdAt: sevenAM, timeZone: utc),
            "Briefing · 07:00"
        )
        let afternoon = sevenAM.addingTimeInterval(8 * 3600 + 5 * 60)
        XCTAssertEqual(
            ProactiveCaption.text(origin: .proactive, sourceLabel: "daily-brief", createdAt: afternoon, timeZone: utc),
            "Briefing · 15:05"
        )
    }

    func testBriefingTimeFollowsTheGivenTimeZone() async {
        let lisbon = TimeZone(identifier: "Europe/Lisbon")! // WEST, UTC+1 in September
        XCTAssertEqual(
            ProactiveCaption.text(origin: .proactive, sourceLabel: "daily-brief", createdAt: sevenAM, timeZone: lisbon),
            "Briefing · 08:00"
        )
    }

    func testBriefingWithoutATimestampDropsTheTime() async {
        XCTAssertEqual(
            ProactiveCaption.text(origin: .proactive, sourceLabel: "daily-brief", createdAt: nil),
            "Briefing"
        )
    }

    func testJobLabelsAreStandingTasks() async {
        for label in ["job-weather-watch", "job-aapl", "job-"] {
            XCTAssertEqual(
                ProactiveCaption.text(origin: .proactive, sourceLabel: label, createdAt: sevenAM),
                "Standing task",
                label
            )
        }
    }

    func testOtherSkillsReadAsFromTheirName() async {
        XCTAssertEqual(
            ProactiveCaption.text(origin: .proactive, sourceLabel: "weekly-review", createdAt: sevenAM),
            "From Weekly review"
        )
        XCTAssertEqual(
            ProactiveCaption.text(origin: .proactive, sourceLabel: "inbox_triage", createdAt: nil),
            "From Inbox triage"
        )
        // "jobs-digest" is a skill, not a `job-` standing task.
        XCTAssertEqual(
            ProactiveCaption.text(origin: .proactive, sourceLabel: "jobs-digest", createdAt: nil),
            "From Jobs digest"
        )
    }

    func testUnlabelledProactiveMessageIsFromHermie() async {
        XCTAssertEqual(ProactiveCaption.text(origin: .proactive, sourceLabel: nil, createdAt: nil), "From Hermie")
        XCTAssertEqual(ProactiveCaption.text(origin: .proactive, sourceLabel: "  ", createdAt: nil), "From Hermie")
    }

    func testMessageCaptionIsAgentOnly() async {
        let agent = ChatViewModel.Message(
            role: .assistant, content: "Rain at 9.", origin: .proactive, sourceLabel: "job-weather"
        )
        XCTAssertEqual(agent.proactiveCaption, "Standing task")
        let user = ChatViewModel.Message(
            role: .user, content: "hi", origin: .proactive, sourceLabel: "job-weather"
        )
        XCTAssertNil(user.proactiveCaption)
        XCTAssertNil(ChatViewModel.Message(role: .assistant, content: "Sure.").proactiveCaption)
    }

    // MARK: - Standing-task confirmation text

    func testConfirmationUsesTheSpecsCondition() async {
        XCTAssertEqual(
            StandingTaskConfirmation.text(
                title: "Weather watch",
                spec: "Check the weather each morning; alert when there are 5 consecutive dry days.",
                scheduleHuman: "Every day at 7:00"
            ),
            "Got it — I'll watch weather watch and ping you when there are 5 consecutive dry days."
        )
        XCTAssertEqual(
            StandingTaskConfirmation.text(
                title: "AAPL price",
                spec: "Notify me if AAPL drops below $150",
                scheduleHuman: nil
            ),
            "Got it — I'll watch AAPL price and ping you when AAPL drops below $150."
        )
    }

    func testConfirmationFallsBackToTheSchedule() async {
        XCTAssertEqual(
            StandingTaskConfirmation.text(
                title: "Tech news",
                spec: "Summarise the top five tech stories.",
                scheduleHuman: "Every day at 8:00 AM"
            ),
            "Got it — I'll watch tech news and ping you every day at 8:00 AM."
        )
    }

    func testConfirmationWithNothingToGoOn() async {
        XCTAssertEqual(
            StandingTaskConfirmation.text(title: nil, spec: nil, scheduleHuman: nil),
            "Got it — I'll watch this and ping you when there's something new."
        )
    }

    func testConfirmationSourceLabelIsAJobSlug() async {
        XCTAssertEqual(StandingTaskConfirmation.sourceLabel(title: "Weather watch: Lisbon!"), "job-weather-watch-lisbon")
        XCTAssertEqual(StandingTaskConfirmation.sourceLabel(title: nil), "job-job")
        XCTAssertEqual(
            ProactiveCaption.text(
                origin: .proactive,
                sourceLabel: StandingTaskConfirmation.sourceLabel(title: "Anything"),
                createdAt: nil
            ),
            "Standing task"
        )
    }

    // MARK: - Snapshot round-trip

    func testSnapshotKeepsOriginAndLabel() async throws {
        let message = ChatViewModel.Message(
            role: .assistant,
            content: "Morning.",
            origin: .proactive,
            sourceLabel: "daily-brief",
            createdAt: sevenAM
        )
        let encoder = JSONEncoder()
        let decoded = try JSONDecoder().decode(ChatViewModel.Message.self, from: encoder.encode(message))
        XCTAssertEqual(decoded.origin, .proactive)
        XCTAssertEqual(decoded.sourceLabel, "daily-brief")
        XCTAssertEqual(decoded.createdAt, sevenAM)
    }

    func testSnapshotsFromOlderBuildsDecodeAsReplies() async throws {
        let legacy = #"{"id":"00000001-1111-4222-8333-444444444444","role":"assistant","content":"hi","sources":[]}"#
        let decoded = try JSONDecoder().decode(ChatViewModel.Message.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.origin, .reply)
        XCTAssertNil(decoded.sourceLabel)
        XCTAssertNil(decoded.proactiveCaption)
    }

    func testUnknownOriginInASnapshotCostsOnlyTheCaption() async throws {
        let future = #"{"id":"00000001-1111-4222-8333-444444444444","role":"assistant","content":"hi","sources":[],"origin":"relayed"}"#
        let decoded = try JSONDecoder().decode(ChatViewModel.Message.self, from: Data(future.utf8))
        XCTAssertEqual(decoded.origin, .reply)
        XCTAssertEqual(decoded.content, "hi")
    }

    // MARK: - Wire → transcript

    func testLoadedThreadCarriesOriginAndSourceLabel() async {
        let conversationID = UUID()
        let client = CaptionConversationsClient(detail: ConversationDetailResponse(
            conversation: ConversationDTO(
                id: conversationID, title: "Hermie", spaceId: nil, createdAt: sevenAM, updatedAt: sevenAM
            ),
            messages: [
                ConversationMessageDTO(
                    id: UUID(), conversationId: conversationID, role: .assistant,
                    content: "Dry all week.", origin: .proactive, sourceLabel: "daily-brief",
                    createdAt: sevenAM
                ),
                ConversationMessageDTO(
                    id: UUID(), conversationId: conversationID, role: .user,
                    content: "thanks", createdAt: sevenAM.addingTimeInterval(60)
                ),
                ConversationMessageDTO(
                    id: UUID(), conversationId: conversationID, role: .assistant,
                    content: "Any time.", createdAt: sevenAM.addingTimeInterval(90)
                ),
            ]
        ))
        let vm = ChatViewModel(client: client)

        await vm.loadConversation(id: conversationID)

        XCTAssertEqual(vm.messages.count, 3)
        XCTAssertEqual(vm.messages[0].origin, .proactive)
        XCTAssertEqual(vm.messages[0].sourceLabel, "daily-brief")
        XCTAssertEqual(vm.messages[0].createdAt, sevenAM)
        XCTAssertNotNil(vm.messages[0].proactiveCaption)
        XCTAssertEqual(vm.messages[2].origin, .reply)
        XCTAssertNil(vm.messages[2].proactiveCaption)
    }
}

// MARK: - Stubs

private struct CaptionConversationsClient: ConversationsClientProtocol {
    let detail: ConversationDetailResponse

    func create(_: ConversationCreateRequest) async throws -> ConversationDTO { detail.conversation }
    func list() async throws -> ConversationListResponse { ConversationListResponse(conversations: []) }
    func get(_: UUID) async throws -> ConversationDetailResponse { detail }
    func delete(_: UUID) async throws {}
    func streamReply(
        conversationID _: UUID,
        request _: MessageStreamRequest
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
