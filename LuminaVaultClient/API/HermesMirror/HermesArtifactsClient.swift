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
}

final class HermesArtifactsHTTPClient: HermesArtifactsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func list(kind: HermesArtifactKind?, query: String?) async throws -> HermesArtifactListResponse {
        try await client.execute(HermesArtifactsEndpoints.List(kind: kind, query: query))
    }
}

enum HermesArtifactsEndpoints {
    struct List: Endpoint {
        typealias Response = HermesArtifactListResponse
        let kind: HermesArtifactKind?
        let query: String?
        var path: String {
            var params: [String] = []
            if let kind { params.append("kind=\(kind.rawValue)") }
            if let query, !query.isEmpty {
                params.append("q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)")
            }
            params.append("limit=100")
            return "/v1/hermes/artifacts?\(params.joined(separator: "&"))"
        }

        var method: HTTPMethod { .get }
    }
}
