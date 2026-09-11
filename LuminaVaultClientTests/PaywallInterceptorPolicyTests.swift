// LuminaVaultClient/LuminaVaultClientTests/PaywallInterceptorPolicyTests.swift
//
// A 402 on a passive screen load used to fire the app-root paywall, sliding
// a sheet over whatever the user was looking at — that is what "opening
// Brain shows an empty sheet" actually was. The Brain graph reads opt out;
// everything the user deliberately reaches for keeps the paywall.

@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

final class PaywallInterceptorPolicyTests: XCTestCase {
    func testBrainGraphReadsDoNotPresentThePaywall() {
        let memory = MemoryGraphEndpoints.Graph(
            limit: 200,
            similarityThreshold: nil,
            maxEdgesPerNode: nil,
            includeWikiPages: true,
            kinds: nil
        )
        XCTAssertFalse(memory.presentsPaywallOn402)

        let knowledge = KnowledgeGraphEndpoints.Graph(limit: 200, minimumConfidence: 0.5)
        XCTAssertFalse(knowledge.presentsPaywallOn402)
    }

    /// The default must stay on, or HER-211 regresses and a user who taps a
    /// paid action gets a bare error instead of the upgrade path.
    ///
    /// Anchored on a skill run rather than chat: running a vault skill is a
    /// deliberate, genuinely Ultimate-only action, so a 402 there *should*
    /// offer the upgrade. Chat used to stand in for "the default" here and no
    /// longer can — see the next test.
    func testDefaultIsToPresentThePaywall() {
        let run = SkillsEndpoints.Run(
            name: "summarize",
            request: SkillRunRequest(input: nil, arguments: nil)
        )
        XCTAssertTrue(run.presentsPaywallOn402)
    }

    /// Chat is free now, and it renders its own failures inline next to the
    /// turn that failed — with an explicit Upgrade button the user chooses to
    /// tap. It must never slide the app-root sheet up on its own.
    ///
    /// Every conversation endpoint is covered, not just the stream: the whole
    /// `/v1/conversations` group is gated on `.memoryQuery` server-side,
    /// *listing included*, so a 402 on `List` would throw a modal over the
    /// Chats tab rather than over a message the user just sent.
    func testChatNeverPresentsThePaywallItself() {
        XCTAssertFalse(
            ChatEndpoints.Completions(request: ChatRequest(messages: [], model: nil))
                .presentsPaywallOn402
        )

        let id = UUID()
        XCTAssertFalse(ConversationsEndpoints.Create(
            request: ConversationCreateRequest(title: nil)
        ).presentsPaywallOn402)
        XCTAssertFalse(ConversationsEndpoints.List().presentsPaywallOn402)
        XCTAssertFalse(ConversationsEndpoints.Get(id: id).presentsPaywallOn402)
        XCTAssertFalse(ConversationsEndpoints.Delete(id: id).presentsPaywallOn402)
        XCTAssertFalse(ConversationsEndpoints.StreamReply(
            conversationID: id,
            request: MessageStreamRequest(content: "hi", multiModel: nil)
        ).presentsPaywallOn402)
    }

    /// Cloud chat posted to `/v1/chat/completions`, which does not exist —
    /// the server registers only `GET /v1/chat/inbox` on that group. The
    /// completions handler is on `/v1/llm`.
    func testCloudChatPostsToTheRouteThatExists() {
        let chat = ChatEndpoints.Completions(
            request: ChatRequest(messages: [], model: nil)
        )
        XCTAssertEqual(chat.path, "/v1/llm/chat")
    }
}
