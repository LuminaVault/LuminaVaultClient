// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockMeetingBriefClient.swift
// Scripted `MeetingBriefClientProtocol`, `APNSPrefsClientProtocol`,
// `CalendarSyncReadinessChecking` and `AppleConsentClientProtocol` fakes,
// plus pre-meeting brief fixtures.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

// `@unchecked` for the same reason as the other scripted mocks: configured in
// the test body and read from the view model's awaits, all on the main actor.
final class MockMeetingBriefClient: MeetingBriefClientProtocol, @unchecked Sendable {
    var result: Result<MeetingBriefResponse, Error>
    private(set) var requestedEventIDs: [UUID] = []

    init(_ response: MeetingBriefResponse = .fixture()) {
        result = .success(response)
    }

    func brief(eventID: UUID) async throws -> MeetingBriefResponse {
        requestedEventIDs.append(eventID)
        return try result.get()
    }
}

// `@unchecked`: same main-actor-only access as above.
final class MockAPNSPrefsClient: APNSPrefsClientProtocol, @unchecked Sendable {
    var response: APNSCategoryPrefsResponse
    var putError: Error?
    private(set) var puts: [APNSCategoryPrefsPutRequest] = []

    init(meetingBriefEnabled: Bool? = nil) {
        response = APNSCategoryPrefsResponse(
            chatEnabled: true,
            nudgeEnabled: true,
            digestEnabled: true,
            meetingBriefEnabled: meetingBriefEnabled
        )
    }

    func get() async throws -> APNSCategoryPrefsResponse {
        response
    }

    func put(_ body: APNSCategoryPrefsPutRequest) async throws -> APNSCategoryPrefsResponse {
        puts.append(body)
        if let putError { throw putError }
        response = APNSCategoryPrefsResponse(
            chatEnabled: body.chatEnabled ?? response.chatEnabled,
            nudgeEnabled: body.nudgeEnabled ?? response.nudgeEnabled,
            digestEnabled: body.digestEnabled ?? response.digestEnabled,
            approvalEnabled: body.approvalEnabled ?? response.approvalEnabled,
            runCompletedEnabled: body.runCompletedEnabled ?? response.runCompletedEnabled,
            meetingBriefEnabled: body.meetingBriefEnabled ?? response.meetingBriefEnabled
        )
        return response
    }
}

struct StubCalendarSyncReadiness: CalendarSyncReadinessChecking {
    let value: CalendarSyncReadiness

    func readiness() async -> CalendarSyncReadiness {
        value
    }
}

/// A fixed `/v1/apple/consent` answer, for the calendar-sync readiness and
/// for building a `DataAccessView` nobody navigates to.
struct StubAppleConsentClient: AppleConsentClientProtocol {
    var consents: [AppleConsentDTO] = []
    var fails = false

    private struct Unreachable: Error {}

    func get() async throws -> AppleConsentResponse {
        if fails { throw Unreachable() }
        return AppleConsentResponse(consents: consents)
    }

    func update(_ request: AppleConsentUpdateRequest) async throws -> AppleConsentResponse {
        AppleConsentResponse(consents: consents)
    }
}

nonisolated extension MeetingBriefResponse {
    static let eventID = UUID(uuidString: "0D000000-0000-4000-8000-000000000001") ?? UUID()
    static let deckMemoryID = UUID(uuidString: "0E000000-0000-4000-8000-000000000001") ?? UUID()
    static let budgetMemoryID = UUID(uuidString: "0E000000-0000-4000-8000-000000000002") ?? UUID()

    /// Wednesday, October 21, 2026, 14:30–15:00 UTC: a design review with
    /// Ana and Rui in Room 4.2, and two notes that bear on it — unless told
    /// there are none.
    static func fixture(memories: [MeetingBriefMemoryDTO]? = nil, why: String? = nil) -> MeetingBriefResponse {
        let memories = memories ?? [
            MeetingBriefMemoryDTO(
                id: deckMemoryID,
                snippet: "Ana wants the Q4 deck to lead with retention, not signups.",
                kind: "preference",
                createdAt: Date(timeIntervalSince1970: 1_791_028_800),
                similarity: 0.81
            ),
            MeetingBriefMemoryDTO(
                id: budgetMemoryID,
                snippet: "Agreed with Rui: the design budget stays flat until the launch.",
                kind: "decision",
                createdAt: Date(timeIntervalSince1970: 1_790_164_800),
                similarity: 0.74
            ),
        ]
        return MeetingBriefResponse(
            event: MeetingBriefEventDTO(
                id: eventID,
                title: "Design review",
                startsAt: Date(timeIntervalSince1970: 1_792_593_000),
                endsAt: Date(timeIntervalSince1970: 1_792_594_800),
                location: "Room 4.2",
                attendees: [
                    CalendarAttendeeDTO(name: "Ana Silva", email: "ana@example.com"),
                    CalendarAttendeeDTO(name: "Rui", email: nil),
                    CalendarAttendeeDTO(name: nil, email: "joana@example.com"),
                ]
            ),
            memories: memories,
            why: why ?? (memories.isEmpty ? "Nothing in your notes matches this meeting yet" : "You mentioned Ana in 2 notes")
        )
    }
}
