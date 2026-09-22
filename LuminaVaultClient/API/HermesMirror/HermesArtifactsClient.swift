import Foundation

enum HermesArtifactKind: String, Codable, Sendable {
    case image, file, link
}

struct HermesArtifactDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let kind: HermesArtifactKind
    let value: String
    let href: String
    let label: String
    let sessionID: String
    let sessionTitle: String
    let occurredAt: Date
}

struct HermesArtifactListResponse: Codable, Sendable, Equatable {
    let artifacts: [HermesArtifactDTO]
    let nextCursor: String?
}

protocol HermesArtifactsClientProtocol: Sendable {
    func list(kind: HermesArtifactKind?, query: String?) async throws -> HermesArtifactListResponse
    /// Artifacts from one Hermes session — what the chat strip shows for the
    /// run behind the conversation on screen. Artifacts key on session, not
    /// conversation, so a conversation that never escalated has none.
    func list(sessionID: String, limit: Int) async throws -> HermesArtifactListResponse
    func get(id: String) async throws -> HermesArtifactDTO
}

final class HermesArtifactsHTTPClient: HermesArtifactsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func list(kind: HermesArtifactKind?, query: String?) async throws -> HermesArtifactListResponse {
        try await client.execute(HermesArtifactsEndpoints.List(kind: kind, query: query))
    }

    func list(sessionID: String, limit: Int) async throws -> HermesArtifactListResponse {
        try await client.execute(HermesArtifactsEndpoints.List(kind: nil, query: nil, sessionID: sessionID, limit: limit))
    }

    func get(id: String) async throws -> HermesArtifactDTO {
        try await client.execute(HermesArtifactsEndpoints.Get(id: id))
    }
}

enum HermesArtifactsEndpoints {
    struct List: Endpoint {
        typealias Response = HermesArtifactListResponse
        let kind: HermesArtifactKind?
        let query: String?
        var sessionID: String?
        var limit = 100
        var path: String {
            var params: [String] = []
            if let kind { params.append("kind=\(kind.rawValue)") }
            if let query, !query.isEmpty {
                params.append("q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)")
            }
            if let sessionID, !sessionID.isEmpty {
                params.append("sessionID=\(Self.encode(sessionID))")
            }
            params.append("limit=\(limit)")
            return "/v1/hermes/artifacts?\(params.joined(separator: "&"))"
        }

        var method: HTTPMethod { .get }

        /// Strict: `.urlQueryAllowed` leaves `&`, `=` and `+` alone, which would
        /// let a value split or reshape the query.
        static func encode(_ value: String) -> String {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-_.~")
            return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }
    }

    struct Get: Endpoint {
        typealias Response = HermesArtifactDTO
        let id: String
        var path: String { "/v1/hermes/artifacts/\(List.encode(id))" }
        var method: HTTPMethod { .get }
    }
}
