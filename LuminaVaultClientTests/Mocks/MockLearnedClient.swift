// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockLearnedClient.swift
// Scripted `LearnedClientProtocol` and `SelfImprovementClientProtocol`
// fakes, plus fixtures for the "What I learned this week" digest.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

// `@unchecked` for the same reason as the other scripted mocks: configured in
// the test body and read from the view model's awaits, all on the main actor.
final class MockLearnedClient: LearnedClientProtocol, @unchecked Sendable {
    var result: Result<LearnedDigestResponse, Error>
    private(set) var requestedSince: [Date?] = []

    init(_ digest: LearnedDigestResponse = .fixture()) {
        result = .success(digest)
    }

    func learned(since: Date?) async throws -> LearnedDigestResponse {
        requestedSince.append(since)
        return try result.get()
    }
}

// `@unchecked`: same main-actor-only access as above. Only `decide` is
// under test; the rest of the Settings pane's surface throws.
final class MockSelfImprovementClient: SelfImprovementClientProtocol, @unchecked Sendable {
    private struct Unscripted: Error {}

    var decideError: Error?
    private(set) var decideCalls: [(id: UUID, approve: Bool)] = []

    func decide(changeID: UUID, approve: Bool) async throws -> LVImprovementChange {
        decideCalls.append((changeID, approve))
        if let decideError { throw decideError }
        return LVImprovementChange(
            id: changeID,
            kind: .soul,
            state: approve ? .approved : .rejected,
            trigger: .weekly,
            title: "",
            summary: "",
            patch: nil,
            reportMarkdown: nil,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    func status() async throws -> LVImprovementStatus { throw Unscripted() }
    func update(_: LVImprovementSettings) async throws -> LVImprovementStatus { throw Unscripted() }
    func runCurator(dryRun _: Bool) async throws -> LVImprovementRun { throw Unscripted() }
    func reviewSoul() async throws -> LVImprovementRun { throw Unscripted() }
    func runs() async throws -> [LVImprovementRun] { throw Unscripted() }
    func resources() async throws -> [LVImprovementResource] { throw Unscripted() }
    func pin(_: LVImprovementResource, pinned _: Bool) async throws -> LVImprovementResource { throw Unscripted() }
    func changes() async throws -> [LVImprovementChange] { throw Unscripted() }
    func rollback(runID _: UUID) async throws -> LVImprovementRun { throw Unscripted() }
}

nonisolated extension LearnedDigestResponse {
    /// Oct 9 – Oct 16, 2026 (UTC noon), two SOUL changes and two memories
    /// unless told otherwise.
    static func fixture(
        soulChanges: [LearnedSoulChangeDTO] = [
            .fixture(title: "You prefer short answers", summary: "Lead with the answer; skip the preamble."),
            .fixture(title: "You work in Lisbon time", summary: "Schedule and reminders use Europe/Lisbon."),
        ],
        memories: [LearnedMemoryDTO] = [
            .fixture(snippet: "Ship on Tuesdays, never Fridays.", kind: "decision"),
            .fixture(snippet: "Prefers Python for one-off scripts.", kind: "preference"),
        ]
    ) -> LearnedDigestResponse {
        LearnedDigestResponse(
            since: Date(timeIntervalSince1970: 1_791_547_200),
            until: Date(timeIntervalSince1970: 1_792_152_000),
            soulChanges: soulChanges,
            memories: memories
        )
    }

    static var empty: LearnedDigestResponse {
        .fixture(soulChanges: [], memories: [])
    }
}

nonisolated extension LearnedSoulChangeDTO {
    static func fixture(
        id: UUID = UUID(),
        title: String = "You prefer short answers",
        summary: String = "Lead with the answer; skip the preamble."
    ) -> LearnedSoulChangeDTO {
        LearnedSoulChangeDTO(id: id, title: title, summary: summary, createdAt: Date(timeIntervalSince1970: 1_791_979_200))
    }
}

nonisolated extension LearnedMemoryDTO {
    static func fixture(
        id: UUID = UUID(),
        snippet: String = "Ship on Tuesdays, never Fridays.",
        kind: String = "decision",
        reviewState: String = "pending"
    ) -> LearnedMemoryDTO {
        LearnedMemoryDTO(
            id: id,
            snippet: snippet,
            kind: kind,
            reviewState: reviewState,
            createdAt: Date(timeIntervalSince1970: 1_791_979_200)
        )
    }
}

nonisolated extension MemoryDTO {
    /// A bare memory for a scripted PATCH answer.
    static func learnedFixture(id: UUID = UUID(), reviewState: String = "approved") -> MemoryDTO {
        MemoryDTO(
            id: id,
            content: "",
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1_791_979_200),
            lat: nil,
            lng: nil,
            accuracyM: nil,
            placeName: nil,
            reviewState: reviewState,
            provenance: nil,
            createdByUserId: nil
        )
    }
}
