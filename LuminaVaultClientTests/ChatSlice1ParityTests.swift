// LuminaVaultClient/LuminaVaultClientTests/ChatSlice1ParityTests.swift
//
// The live context gauge, the live tool count, and composer drops.
//
// Each is a "say nothing rather than something wrong" rule: no gauge without
// both numbers, no double-counted tools, and one unreadable file in a drop
// does not cost the readable ones.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

final class ChatContextGaugeTests: XCTestCase {
    private func routing(prompt: Int? = nil, window: Int? = nil, dropped: Int? = nil) -> RouterRoutingEventDTO {
        RouterRoutingEventDTO(
            executionID: UUID(),
            phase: .selected,
            profileID: UUID(),
            profileName: "Auto",
            taskType: .general,
            strategy: .sequential,
            activeRoutes: [],
            promptTokens: prompt,
            contextWindowTokens: window,
            droppedHistoryTurns: dropped
        )
    }

    private func usage(window: Int?) -> RouterUsageDTO {
        RouterUsageDTO(
            executionID: UUID(),
            tokensIn: 1,
            tokensOut: 1,
            estimatedCostUsdMicros: 0,
            latencyMs: 1,
            usageEstimated: false,
            contextWindowTokens: window
        )
    }

    func testReadsPromptOverWindow() {
        let reading = ChatContextGauge.Reading.make(routing: routing(prompt: 50_000, window: 100_000), usage: nil)
        XCTAssertEqual(reading?.percent, 50)
        XCTAssertEqual(reading?.isNearlyFull, false)
    }

    /// The rule the gauge hangs on: a wrong gauge is worse than none.
    func testNoGaugeWithoutAPromptSize() {
        XCTAssertNil(ChatContextGauge.Reading.make(routing: routing(window: 100_000), usage: nil))
    }

    /// The managed-tenant case: the window is scrubbed, so there is no gauge.
    func testNoGaugeWithoutAWindow() {
        XCTAssertNil(ChatContextGauge.Reading.make(routing: routing(prompt: 10), usage: nil))
        XCTAssertNil(ChatContextGauge.Reading.make(routing: routing(prompt: 10, window: 0), usage: nil))
    }

    func testFallsBackToTheUsageWindow() {
        let reading = ChatContextGauge.Reading.make(routing: routing(prompt: 25), usage: usage(window: 100))
        XCTAssertEqual(reading?.percent, 25)
    }

    func testClampsAnOverfullPrompt() {
        let reading = ChatContextGauge.Reading.make(routing: routing(prompt: 150, window: 100), usage: nil)
        XCTAssertEqual(reading?.percent, 100)
        XCTAssertEqual(reading?.isNearlyFull, true)
    }

    func testDroppedTurnsAreSaidAloud() {
        let make = { (dropped: Int?) in
            ChatContextGauge.Reading.make(routing: self.routing(prompt: 1, window: 10, dropped: dropped), usage: nil)?
                .droppedPhrase
        }
        XCTAssertNil(make(nil))
        XCTAssertNil(make(0))
        XCTAssertEqual(make(1), "1 earlier turn dropped to fit")
        XCTAssertEqual(make(3), "3 earlier turns dropped to fit")
    }
}

@MainActor
final class ChatRunFollowerToolCountTests: XCTestCase {
    /// A start and its completion are both `.tool` rows. Counting rows would
    /// report every call twice.
    func testCountsCallsNotRows() async {
        let follower = ChatRunFollower(client: StubHermesRunsClient(), runID: UUID())
        follower.apply(.stub(seq: 1, event: "run.started"))
        follower.apply(.stub(seq: 2, event: "tool.started", fields: ["tool": .string("search")]))
        follower.apply(.stub(seq: 3, event: "tool.completed", fields: ["tool": .string("search")]))
        follower.apply(.stub(seq: 4, event: "tool.started", fields: ["tool": .string("read")]))
        follower.apply(.stub(seq: 5, event: "tool.failed", fields: ["tool": .string("read")]))

        XCTAssertEqual(follower.toolCallCount, 2)
    }

    /// Replay-then-live re-sends what the follower already holds.
    func testAReplayedStartIsNotCountedTwice() async {
        let follower = ChatRunFollower(client: StubHermesRunsClient(), runID: UUID())
        follower.apply(.stub(seq: 1, event: "tool.started"))
        follower.apply(.stub(seq: 1, event: "tool.started"))
        XCTAssertEqual(follower.toolCallCount, 1)
    }
}

final class ChatDropStagingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ name: String, _ contents: String) throws -> URL {
        let url = directory.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testOneBadFileDoesNotCostTheGoodOnes() async throws {
        let good = try file("notes.md", "# Plan")
        let bad = try file("photo.png", "not really a png")
        let empty = try file("blank.txt", "   ")

        let outcome = await ChatDropStaging.stage([good, bad, empty])

        XCTAssertEqual(outcome.staged.map(\.name), ["notes.md"])
        XCTAssertEqual(outcome.failures.count, 2)
        XCTAssertTrue(outcome.failures[0].hasPrefix("photo.png:"))
    }

    /// The drop copy keeps the original name, which is both the chip label
    /// and how the extractor decides what it is reading.
    func testTheDropCopyKeepsItsName() throws {
        let source = try file("report.pdf", "x")
        let item = try ChatDropItem(copying: source)
        XCTAssertEqual(item.url.lastPathComponent, "report.pdf")
        XCTAssertNotEqual(item.url, source)
    }
}
