// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockBriefClient.swift
// Scripted `BriefClientProtocol` and `CommitmentsClientProtocol` fakes, plus
// fixtures for the daily brief and its open loops.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

// `@unchecked` for the same reason as the other scripted mocks: configured in
// the test body and read from the view model's awaits, all on the main actor.
final class MockBriefClient: BriefClientProtocol, @unchecked Sendable {
    var result: Result<MeBriefResponse, Error>
    var feedbackError: Error?
    private(set) var requestedDates: [String?] = []
    private(set) var feedbackCalls: [(briefID: UUID, cardID: String, action: BriefCardFeedbackAction)] = []

    init(_ brief: BriefDTO? = .fixture()) {
        result = .success(MeBriefResponse(brief: brief))
    }

    func brief(date: String?) async throws -> MeBriefResponse {
        requestedDates.append(date)
        return try result.get()
    }

    func feedback(briefID: UUID, cardID: String, action: BriefCardFeedbackAction) async throws {
        feedbackCalls.append((briefID, cardID, action))
        if let feedbackError { throw feedbackError }
    }
}

// `@unchecked`: same main-actor-only access as above.
final class MockCommitmentsClient: CommitmentsClientProtocol, @unchecked Sendable {
    var results: [CommitmentsQueryState: Result<CommitmentsResponse, Error>] = [:]
    var updateError: Error?
    private(set) var requestedStates: [CommitmentsQueryState] = []
    private(set) var updateCalls: [(id: UUID, state: CommitmentState)] = []

    init(open: [CommitmentDTO] = CommitmentDTO.openFixtures) {
        results[.open] = .success(CommitmentsResponse(items: open))
    }

    func commitments(state: CommitmentsQueryState) async throws -> CommitmentsResponse {
        requestedStates.append(state)
        guard let result = results[state] else { return CommitmentsResponse(items: []) }
        return try result.get()
    }

    func update(id: UUID, state: CommitmentState) async throws -> CommitmentDTO {
        updateCalls.append((id, state))
        if let updateError { throw updateError }
        return CommitmentDTO(id: id, text: "", state: state, createdAt: Date(timeIntervalSince1970: 1_792_400_000))
    }
}

nonisolated extension CommitmentDTO {
    static let sendDeckID = UUID(uuidString: "0A000000-0000-4000-8000-000000000001") ?? UUID()
    static let callMomID = UUID(uuidString: "0A000000-0000-4000-8000-000000000002") ?? UUID()
    static let renewID = UUID(uuidString: "0A000000-0000-4000-8000-000000000003") ?? UUID()

    /// 2026-10-20T12:00:00Z — the day the brief fixtures are "today".
    static let fixtureNow = Date(timeIntervalSince1970: 1_792_497_600)

    static func fixture(
        id: UUID = UUID(),
        text: String = "Send Ana the deck",
        dueAt: Date? = nil,
        state: CommitmentState = .open,
        doneAt: Date? = nil
    ) -> CommitmentDTO {
        CommitmentDTO(
            id: id,
            text: text,
            dueAt: dueAt,
            state: state,
            surfacedCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_792_065_600),
            doneAt: doneAt
        )
    }

    /// Three open loops: one overdue, one due today, one without a date.
    static var openFixtures: [CommitmentDTO] {
        [
            .fixture(id: sendDeckID, text: "Send Ana the deck", dueAt: Date(timeIntervalSince1970: 1_792_324_800)),
            .fixture(id: callMomID, text: "Call Mom about the weekend", dueAt: fixtureNow),
            .fixture(id: renewID, text: "Renew the passport"),
        ]
    }
}

nonisolated extension BriefDTO {
    static let fixtureID = UUID(uuidString: "0B000000-0000-4000-8000-000000000001") ?? UUID()
    static let revisitMemoryID = UUID(uuidString: "0C000000-0000-4000-8000-000000000001") ?? UUID()

    /// Tuesday, October 20, 2026 with today, open loops, to revisit and
    /// weather cards, unless told otherwise.
    static func fixture(cards: [BriefCardDTO]? = nil) -> BriefDTO {
        BriefDTO(
            id: fixtureID,
            date: "2026-10-20",
            cards: cards ?? [
                BriefCardDTO(
                    id: "today",
                    kind: .today,
                    title: "Today",
                    body: "- 09:30 Standup\n- 14:00 Design review with **Ana**",
                    why: "2 events on your calendar",
                    refs: [BriefCardRefDTO(kind: .event, id: "evt-1")]
                ),
                BriefCardDTO(
                    id: "openLoops",
                    kind: .openLoops,
                    title: "Open loops",
                    body: "- Send Ana the deck\n- Call Mom about the weekend\n- Renew the passport",
                    why: "You said you'd do these — one is overdue",
                    refs: CommitmentDTO.openFixtures.map { BriefCardRefDTO(kind: .commitment, id: $0.id.uuidString) }
                ),
                BriefCardDTO(
                    id: "toRevisit",
                    kind: .toRevisit,
                    title: "To revisit",
                    body: "Ship on Tuesdays, never Fridays.",
                    why: "Saved a year ago today",
                    refs: [BriefCardRefDTO(kind: .memory, id: revisitMemoryID.uuidString)]
                ),
                BriefCardDTO(
                    id: "weather",
                    kind: .weather,
                    title: "Weather",
                    body: "Lisbon: 19° and clear, light wind.",
                    why: "You asked for the weather each morning"
                ),
            ],
            endNote: "That's it for today.",
            createdAt: Date(timeIntervalSince1970: 1_792_479_600)
        )
    }
}
