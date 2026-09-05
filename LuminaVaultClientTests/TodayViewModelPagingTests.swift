// LuminaVaultClient/LuminaVaultClientTests/TodayViewModelPagingTests.swift
//
// Hermes Companion Phase 2 — the Today feed now unions Hermes job runs, so a
// busy machine can push a week of history past one page. These cover the
// `before` cursor that pages behind it.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class TodayViewModelPagingTests: XCTestCase {
    private var client: StubTodayClient!
    private var sut: TodayViewModel!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "lv.today.lastSeenISO")
        client = StubTodayClient()
        sut = TodayViewModel(client: client)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "lv.today.lastSeenISO")
        super.tearDown()
    }

    func testRefreshKeepsTheCursorForThePageBehind() async {
        client.responses = [
            .init(outputs: [.stub(id: 1, at: 3_000)], streakDays: 4, activeRun: false, nextCursor: "2026-09-04T00:00:00Z"),
        ]

        await sut.refresh()

        XCTAssertEqual(sut.state, .loaded)
        XCTAssertEqual(sut.nextCursor, "2026-09-04T00:00:00Z")
        // The first page is the newest one — no `before`.
        XCTAssertEqual(client.calls.first?.before, nil)
    }

    func testLoadMoreSendsTheCursorAsBeforeAndAppendsOlderRows() async {
        client.responses = [
            .init(outputs: [.stub(id: 1, at: 3_000)], streakDays: 0, activeRun: false, nextCursor: "1970-01-01T00:50:00Z"),
            .init(outputs: [.stub(id: 2, at: 2_000)], streakDays: 0, activeRun: false, nextCursor: nil),
        ]

        await sut.refresh()
        await sut.loadMore()

        XCTAssertEqual(client.calls.count, 2)
        XCTAssertEqual(client.calls[1].before, Date(timeIntervalSince1970: 3_000))
        XCTAssertEqual(sut.outputs.map(\.headline), ["output-1", "output-2"])
        // A short page means nothing is behind it.
        XCTAssertNil(sut.nextCursor)
    }

    func testLoadMoreIsANoOpOnceTheServerStopsHandingBackACursor() async {
        client.responses = [
            .init(outputs: [.stub(id: 1, at: 3_000)], streakDays: 0, activeRun: false, nextCursor: nil),
        ]

        await sut.refresh()
        await sut.loadMore()

        XCTAssertEqual(client.calls.count, 1)
    }

    /// The cursor is an exclusive bound, but a write landing between the two
    /// reads can still overlap — the same row must not appear twice.
    func testAnOverlappingPageDoesNotDuplicateRows() async {
        client.responses = [
            .init(outputs: [.stub(id: 1, at: 3_000)], streakDays: 0, activeRun: false, nextCursor: "1970-01-01T00:50:00Z"),
            .init(outputs: [.stub(id: 1, at: 3_000), .stub(id: 2, at: 2_000)], streakDays: 0, activeRun: false, nextCursor: nil),
        ]

        await sut.refresh()
        await sut.loadMore()

        XCTAssertEqual(sut.outputs.count, 2)
    }

    /// A failed page must not blank the rows already on screen.
    func testPagingFailureKeepsTheFeed() async {
        client.responses = [
            .init(outputs: [.stub(id: 1, at: 3_000)], streakDays: 0, activeRun: false, nextCursor: "1970-01-01T00:50:00Z"),
        ]
        await sut.refresh()

        client.failNext = true
        await sut.loadMore()

        XCTAssertEqual(sut.state, .loaded)
        XCTAssertEqual(sut.outputs.count, 1)
        XCTAssertNil(sut.nextCursor)
    }
}

private extension SkillOutputDTO {
    static func stub(id: Int, at epoch: TimeInterval, source: SkillSource = .builtin) -> SkillOutputDTO {
        SkillOutputDTO(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))
                ?? UUID(),
            skillName: "daily-brief",
            source: source,
            kind: .dailyBrief,
            headline: "output-\(id)",
            body: "body",
            createdAt: Date(timeIntervalSince1970: epoch)
        )
    }
}

private final class StubTodayClient: TodayClientProtocol, @unchecked Sendable {
    struct Call: Equatable {
        let since: Date?
        let before: Date?
        let limit: Int?
    }

    var responses: [SkillOutputListResponse] = []
    var failNext = false
    private(set) var calls: [Call] = []

    func outputs(since: Date?, before: Date?, limit: Int?) async throws -> SkillOutputListResponse {
        calls.append(Call(since: since, before: before, limit: limit))
        if failNext {
            failNext = false
            throw APIError.networkFailure(URLError(.notConnectedToInternet))
        }
        guard !responses.isEmpty else {
            return SkillOutputListResponse(outputs: [], streakDays: 0, activeRun: false)
        }
        return responses.removeFirst()
    }
}
