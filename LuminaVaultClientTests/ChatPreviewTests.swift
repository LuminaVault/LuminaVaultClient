// LuminaVaultClient/LuminaVaultClientTests/ChatPreviewTests.swift
//
// The preview address contract and the register-versus-open rule.
//
// The address strings are pinned literally because they are shared with the
// web client (`src/lib/chat/preview-target.test.ts` pins the same ones). A
// link emitted by either client has to open in the other.

import XCTest
@testable import LuminaVaultClient

final class ChatPreviewTargetTests: XCTestCase {
    func testAddressesMatchTheWebClientByteForByte() {
        XCTAssertEqual(ChatPreviewTarget.artifact(id: "a1").address, "lv://artifact/a1")
        XCTAssertEqual(ChatPreviewTarget.vaultFile(path: "notes/plan.md").address, "lv://vault/notes/plan.md")
        XCTAssertEqual(
            ChatPreviewTarget.vaultFile(path: "a b/c&d/e.md").address,
            "lv://vault/a%20b/c%26d/e.md"
        )
        XCTAssertEqual(ChatPreviewTarget.toolOutput(runID: "r1", seq: 7).address, "lv://run/r1/event/7")
        XCTAssertEqual(
            ChatPreviewTarget.url(URL(string: "https://example.com")!).address,
            "https://example.com"
        )
    }

    func testEveryKindRoundTrips() {
        let targets: [ChatPreviewTarget] = [
            .artifact(id: "3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
            .vaultFile(path: "a b/c&d/e.md"),
            .toolOutput(runID: "run/with/slashes", seq: 12),
            .url(URL(string: "https://example.com/deep?q=1")!),
        ]
        for target in targets {
            XCTAssertEqual(ChatPreviewTarget(address: target.address), target, target.address)
        }
    }

    /// Only http(s) may reach a renderer.
    func testRefusesSchemesThatCouldExecute() {
        for address in ["javascript:alert(1)", "data:text/html,hi", "file:///etc/passwd", "ftp://x"] {
            XCTAssertNil(ChatPreviewTarget(address: address), address)
        }
    }

    /// The same malformed list the web test uses.
    func testMalformedAddressesOpenNothing() {
        for address in [
            "", "lv://", "lv://artifact/", "lv://artifact/a/b", "lv://vault/",
            "lv://run/abc/event/", "lv://run/abc/event/not-a-number",
            "lv://run/abc/event/1/extra", "lv://unknown/thing",
            "lv://run/abc/event/-1", "lv://run/abc/event/+1",
        ] {
            XCTAssertNil(ChatPreviewTarget(address: address), address)
        }
    }

    func testLabels() {
        XCTAssertEqual(ChatPreviewTarget.vaultFile(path: "notes/2026/plan.md").label, "plan.md")
        XCTAssertEqual(ChatPreviewTarget.url(URL(string: "https://example.com/deep/path")!).label, "example.com")
    }
}

@MainActor
final class ChatPreviewStoreTests: XCTestCase {
    /// The load-bearing test: a tool producing something must never open the
    /// pane on the reader's behalf.
    func testRegisteringACandidateNeverOpensThePane() async {
        let store = ChatPreviewStore()
        store.registerCandidate(.artifact(id: "a"))
        store.registerCandidate(.toolOutput(runID: "r", seq: 1))

        XCTAssertFalse(store.isOpen)
        XCTAssertNil(store.target)
        XCTAssertEqual(store.candidates.count, 2)
    }

    func testOpenShowsTheTarget() async {
        let store = ChatPreviewStore()
        store.open(.artifact(id: "a"))
        XCTAssertTrue(store.isOpen)
        XCTAssertEqual(store.target, .artifact(id: "a"))
    }

    func testCandidatesAreDedupedNewestFirstAndCapped() async {
        let store = ChatPreviewStore()
        store.registerCandidate(.artifact(id: "a"))
        store.registerCandidate(.artifact(id: "b"))
        store.registerCandidate(.artifact(id: "a"))
        XCTAssertEqual(store.candidates, [.artifact(id: "b"), .artifact(id: "a")])

        for index in 0 ..< 100 {
            store.registerCandidate(.toolOutput(runID: "r", seq: index))
        }
        XCTAssertEqual(store.candidates.count, ChatPreviewStore.maxCandidates)
    }

    func testABadDeepLinkOpensNothing() async {
        let store = ChatPreviewStore()
        XCTAssertFalse(store.open(address: "javascript:alert(1)"))
        XCTAssertFalse(store.open(address: nil))
        XCTAssertFalse(store.isOpen)
        XCTAssertTrue(store.open(address: "lv://artifact/x"))
        XCTAssertTrue(store.isOpen)
    }

    /// A new conversation must not offer the previous one's previews.
    func testResetForgetsTheConversation() async {
        let store = ChatPreviewStore()
        store.registerCandidate(.artifact(id: "a"))
        store.open(.artifact(id: "a"))
        store.reset()
        XCTAssertTrue(store.candidates.isEmpty)
        XCTAssertNil(store.target)
        XCTAssertFalse(store.isOpen)
    }
}
