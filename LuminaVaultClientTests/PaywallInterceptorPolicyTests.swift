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
    func testDefaultIsToPresentThePaywall() {
        let chat = ChatEndpoints.Completions(
            request: ChatRequest(messages: [], model: nil)
        )
        XCTAssertTrue(chat.presentsPaywallOn402)
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
