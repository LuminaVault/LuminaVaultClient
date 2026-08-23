// LuminaVaultClient/LuminaVaultClientTests/ChatHistoryStoreTests.swift
//
// HER-107 — covers ChatHistoryStore round-trip, the 50-turn FIFO cap,
// per-conversation isolation, and most-recent-loads-first ordering.
// Each test uses a unique temp directory so concurrent test runs don't
// race on the file URL.
import XCTest
@testable import LuminaVaultClient

final class ChatHistoryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatHistoryStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private func makeStore() -> ChatHistoryStore {
        ChatHistoryStore(baseURL: tempDir)
    }

    private func snap(id: UUID = UUID(), messages: [ChatViewModel.Message]) -> ChatHistoryStore.Snapshot {
        ChatHistoryStore.Snapshot(
            id: id,
            transport: .memoryGrounded,
            messages: messages,
            updatedAt: Date(),
        )
    }

    private func userMessage(_ content: String) -> ChatViewModel.Message {
        ChatViewModel.Message(role: .user, content: content)
    }

    func testSaveAndLoadRoundTrip() async throws {
        let store = makeStore()
        let id = UUID()
        let original = snap(id: id, messages: [
            userMessage("hello"),
            .init(role: .assistant, content: "hi"),
        ])
        try await store.save(original)

        let loaded = try await store.load(conversationID: id)
        XCTAssertEqual(loaded?.messages.map(\.content), ["hello", "hi"])
        XCTAssertEqual(loaded?.transport, .memoryGrounded)
    }

    func testCapsAt50Turns() async throws {
        let store = makeStore()
        let id = UUID()
        let many = (0..<75).map { userMessage("turn \($0)") }
        try await store.save(snap(id: id, messages: many))

        let loaded = try await store.load(conversationID: id)
        XCTAssertEqual(loaded?.messages.count, ChatHistoryStore.maxTurns)
        // FIFO: oldest dropped, latest preserved.
        XCTAssertEqual(loaded?.messages.first?.content, "turn 25")
        XCTAssertEqual(loaded?.messages.last?.content, "turn 74")
    }

    func testReplacesExistingConversation() async throws {
        let store = makeStore()
        let id = UUID()
        try await store.save(snap(id: id, messages: [userMessage("first")]))
        try await store.save(snap(id: id, messages: [userMessage("replaced")]))

        let loaded = try await store.load(conversationID: id)
        XCTAssertEqual(loaded?.messages.map(\.content), ["replaced"])
    }

    func testMultipleConversationsCoexist() async throws {
        let store = makeStore()
        let aID = UUID()
        let bID = UUID()
        try await store.save(snap(id: aID, messages: [userMessage("a")]))
        try await store.save(snap(id: bID, messages: [userMessage("b")]))

        let a = try await store.load(conversationID: aID)
        let b = try await store.load(conversationID: bID)
        XCTAssertEqual(a?.messages.first?.content, "a")
        XCTAssertEqual(b?.messages.first?.content, "b")
    }

    func testLoadMostRecentReturnsLatestUpdate() async throws {
        let store = makeStore()
        let aID = UUID()
        let bID = UUID()
        try await store.save(ChatHistoryStore.Snapshot(
            id: aID, transport: .memoryGrounded,
            messages: [userMessage("old")],
            updatedAt: Date(timeIntervalSince1970: 1_000),
        ))
        try await store.save(ChatHistoryStore.Snapshot(
            id: bID, transport: .fresh,
            messages: [userMessage("new")],
            updatedAt: Date(timeIntervalSince1970: 2_000),
        ))

        let mostRecent = try await store.loadMostRecent()
        XCTAssertEqual(mostRecent?.id, bID)
        XCTAssertEqual(mostRecent?.transport, .fresh)
    }

    func testClearRemovesOnlyTargetedConversation() async throws {
        let store = makeStore()
        let keepID = UUID()
        let killID = UUID()
        try await store.save(snap(id: keepID, messages: [userMessage("keep")]))
        try await store.save(snap(id: killID, messages: [userMessage("kill")]))
        try await store.clear(conversationID: killID)

        let keep = try await store.load(conversationID: keepID)
        let kill = try await store.load(conversationID: killID)
        XCTAssertNotNil(keep)
        XCTAssertNil(kill)
    }

    func testClearAllWipesEverything() async throws {
        let store = makeStore()
        try await store.save(snap(messages: [userMessage("a")]))
        try await store.save(snap(messages: [userMessage("b")]))
        try await store.clearAll()

        let mostRecent = try await store.loadMostRecent()
        XCTAssertNil(mostRecent)
    }

    // MARK: - lastReadMessageID (scroll restore)

    func testLastReadMessageIDRoundTrips() async throws {
        let store = makeStore()
        let id = UUID()
        let anchor = userMessage("second")
        var snapshot = snap(id: id, messages: [userMessage("first"), anchor])
        snapshot.lastReadMessageID = anchor.id
        try await store.save(snapshot)

        let loaded = try await store.load(conversationID: id)
        XCTAssertEqual(loaded?.lastReadMessageID, anchor.id)
    }

    /// `lastReadMessageID` was added after the store shipped. Snapshots
    /// written before it must still decode — to `nil`, which restores to the
    /// bottom exactly as the old build did.
    func testSnapshotWithoutLastReadMessageIDDecodesToNil() throws {
        let id = UUID()
        let messageID = UUID()
        let json = """
        {
          "conversations": [
            {
              "id": "\(id.uuidString)",
              "transport": "memory_grounded",
              "updatedAt": "2026-01-01T00:00:00Z",
              "messages": [
                {
                  "id": "\(messageID.uuidString)",
                  "role": "user",
                  "content": "legacy turn",
                  "sources": [],
                  "imageURLs": [],
                  "renderedMarkdown": "legacy turn"
                }
              ]
            }
          ]
        }
        """
        let url = tempDir.appendingPathComponent(ChatHistoryStore.fileName)
        try Data(json.utf8).write(to: url)

        // Decode through the same path the store uses.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct Container: Decodable { let conversations: [ChatHistoryStore.Snapshot] }
        let decoded = try decoder.decode(Container.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.conversations.count, 1)
        XCTAssertNil(decoded.conversations[0].lastReadMessageID)
        XCTAssertEqual(decoded.conversations[0].messages.map(\.content), ["legacy turn"])
    }

    func testLegacySnapshotOnDiskLoadsThroughTheStore() async throws {
        let id = UUID()
        let json = """
        {"conversations":[{"id":"\(id.uuidString)","transport":"fresh",\
        "updatedAt":"2026-01-01T00:00:00Z","messages":[]}]}
        """
        try Data(json.utf8).write(to: tempDir.appendingPathComponent(ChatHistoryStore.fileName))

        let loaded = try await makeStore().load(conversationID: id)
        XCTAssertNotNil(loaded, "a pre-lastReadMessageID file must not be treated as corrupt")
        XCTAssertNil(loaded?.lastReadMessageID)
    }
}
