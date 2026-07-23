import Foundation

enum LVImprovementModelMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case economy, main
    var id: String { rawValue }
}

enum LVImprovementAvailability: String, Codable, Sendable {
    case managed
    case compatibleBYO = "compatible_byo"
    case readOnly = "read_only"
    case unavailable
}

enum LVImprovementKind: String, Codable, Sendable { case curator, soul }
enum LVImprovementTrigger: String, Codable, Sendable { case manual, weekly, complexSession = "complex_session" }
enum LVImprovementRunStatus: String, Codable, Sendable { case queued, running, succeeded, failed, rolledBack = "rolled_back" }
enum LVImprovementChangeState: String, Codable, Sendable { case pending, approved, rejected, applied, stale, failed }
enum LVImprovementResourceKind: String, Codable, Sendable { case skill, job }
enum LVImprovementResourceState: String, Codable, Sendable { case active, stale, archived }

struct LVImprovementSettings: Codable, Equatable, Sendable {
    var enabled = true
    var curatorEnabled = true
    var intervalHours = 168
    var minimumIdleHours = 2
    var consolidate = true
    var pruneBuiltins = false
    var backupKeep = 5
    var soulReviewEnabled = true
    var reviewComplexSessions = true
    var soulReviewWindowDays = 14
    var soulReviewCooldownHours = 24
    var modelMode: LVImprovementModelMode = .economy
}

struct LVImprovementStatus: Codable, Sendable {
    let settings: LVImprovementSettings
    let availability: LVImprovementAvailability
    let economyModelAvailable: Bool
    let pendingChanges: Int
    let lastCuratorReviewAt: Date?
    let lastSoulReviewAt: Date?
    let nextReviewAt: Date?
    let message: String?
}

struct LVImprovementRun: Codable, Sendable, Identifiable {
    let id: UUID
    let kind: LVImprovementKind
    let status: LVImprovementRunStatus
    let trigger: LVImprovementTrigger
    let dryRun: Bool
    let modelUsed: String?
    let reportMarkdown: String?
    let actionsApplied: Int
    let actionsSkipped: Int
    let startedAt: Date?
    let endedAt: Date?
    let createdAt: Date
    let failureReason: String?
}

struct LVImprovementChange: Codable, Sendable, Identifiable {
    let id: UUID
    let kind: LVImprovementKind
    let state: LVImprovementChangeState
    let trigger: LVImprovementTrigger
    let title: String
    let summary: String
    let patch: String?
    let reportMarkdown: String?
    let createdAt: Date
}

struct LVImprovementResource: Codable, Sendable, Identifiable {
    var id: String { "\(kind.rawValue):\(name)" }
    let name: String
    let title: String
    let kind: LVImprovementResourceKind
    let state: LVImprovementResourceState
    let pinned: Bool
    let curatorManaged: Bool
    let lastActivityAt: Date?
}

private struct SettingsRequest: Encodable { let settings: LVImprovementSettings }
private struct RunRequest: Encodable { let dryRun: Bool }
private struct RunResponse: Decodable { let run: LVImprovementRun }
private struct RunsResponse: Decodable { let runs: [LVImprovementRun] }
private struct ChangesResponse: Decodable { let changes: [LVImprovementChange] }
private struct DecisionResponse: Decodable { let change: LVImprovementChange }
private struct ResourcesResponse: Decodable { let skills: [LVImprovementResource] }
private struct PinRequest: Encodable { let pinned: Bool }

private enum SelfImprovementEndpoints {
    struct Status: Endpoint {
        typealias Response = LVImprovementStatus
        let request: SettingsRequest?
        var path: String { "/v1/me/improvement" }
        var method: HTTPMethod { request == nil ? .get : .put }
        var body: (any Encodable)? { request }
    }
    struct Curator: Endpoint {
        typealias Response = RunResponse
        let request: RunRequest
        var path: String { "/v1/me/improvement/curator/runs" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }
    struct SoulReview: Endpoint {
        typealias Response = RunResponse
        var path: String { "/v1/me/improvement/soul/reviews" }
        var method: HTTPMethod { .post }
    }
    struct Runs: Endpoint {
        typealias Response = RunsResponse
        var path: String { "/v1/me/improvement/runs?limit=30" }
        var method: HTTPMethod { .get }
    }
    struct Resources: Endpoint {
        typealias Response = ResourcesResponse
        var path: String { "/v1/me/improvement/resources" }
        var method: HTTPMethod { .get }
    }
    struct Pin: Endpoint {
        typealias Response = LVImprovementResource
        let kind: LVImprovementResourceKind
        let name: String
        let request: PinRequest
        var path: String {
            let safeName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            return "/v1/me/improvement/resources/\(kind.rawValue)/\(safeName)"
        }
        var method: HTTPMethod { .patch }
        var body: (any Encodable)? { request }
    }
    struct Changes: Endpoint {
        typealias Response = ChangesResponse
        var path: String { "/v1/me/improvement/changes" }
        var method: HTTPMethod { .get }
    }
    struct Decide: Endpoint {
        typealias Response = DecisionResponse
        let id: UUID
        let approve: Bool
        var path: String { "/v1/me/improvement/changes/\(id.uuidString)/\(approve ? "approve" : "reject")" }
        var method: HTTPMethod { .post }
    }
    struct Rollback: Endpoint {
        typealias Response = RunResponse
        let id: UUID
        var path: String { "/v1/me/improvement/runs/\(id.uuidString)/rollback" }
        var method: HTTPMethod { .post }
    }
}

protocol SelfImprovementClientProtocol: Sendable {
    func status() async throws -> LVImprovementStatus
    func update(_ settings: LVImprovementSettings) async throws -> LVImprovementStatus
    func runCurator(dryRun: Bool) async throws -> LVImprovementRun
    func reviewSoul() async throws -> LVImprovementRun
    func runs() async throws -> [LVImprovementRun]
    func resources() async throws -> [LVImprovementResource]
    func pin(_ resource: LVImprovementResource, pinned: Bool) async throws -> LVImprovementResource
    func changes() async throws -> [LVImprovementChange]
    func decide(changeID: UUID, approve: Bool) async throws -> LVImprovementChange
    func rollback(runID: UUID) async throws -> LVImprovementRun
}

final class SelfImprovementHTTPClient: SelfImprovementClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func status() async throws -> LVImprovementStatus {
        try await client.execute(SelfImprovementEndpoints.Status(request: nil))
    }
    func update(_ settings: LVImprovementSettings) async throws -> LVImprovementStatus {
        try await client.execute(SelfImprovementEndpoints.Status(request: SettingsRequest(settings: settings)))
    }
    func runCurator(dryRun: Bool) async throws -> LVImprovementRun {
        try await client.execute(SelfImprovementEndpoints.Curator(request: RunRequest(dryRun: dryRun))).run
    }
    func reviewSoul() async throws -> LVImprovementRun {
        try await client.execute(SelfImprovementEndpoints.SoulReview()).run
    }
    func runs() async throws -> [LVImprovementRun] {
        try await client.execute(SelfImprovementEndpoints.Runs()).runs
    }
    func resources() async throws -> [LVImprovementResource] {
        try await client.execute(SelfImprovementEndpoints.Resources()).skills
    }
    func pin(_ resource: LVImprovementResource, pinned: Bool) async throws -> LVImprovementResource {
        try await client.execute(SelfImprovementEndpoints.Pin(
            kind: resource.kind,
            name: resource.name,
            request: PinRequest(pinned: pinned)
        ))
    }
    func changes() async throws -> [LVImprovementChange] {
        try await client.execute(SelfImprovementEndpoints.Changes()).changes
    }
    func decide(changeID: UUID, approve: Bool) async throws -> LVImprovementChange {
        try await client.execute(SelfImprovementEndpoints.Decide(id: changeID, approve: approve)).change
    }
    func rollback(runID: UUID) async throws -> LVImprovementRun {
        try await client.execute(SelfImprovementEndpoints.Rollback(id: runID)).run
    }
}
