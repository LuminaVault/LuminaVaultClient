// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultEndpoints.swift
// HER-35: POST /v1/vault/create + GET /v1/vault/status.
// HER-105: GET /v1/vault/files (list with space/q/before/after/limit),
//          POST /v1/vault/files/move, DELETE /v1/vault/files/{path}.
// Note: GET /v1/vault/files/{path} (raw bytes) is *not* expressed here
// as an Endpoint because it returns binary rather than JSON; the read
// path lives directly on `VaultHTTPClient.readFile` via
// `BaseHTTPClient.fetchBytes`.
import Foundation

enum VaultEndpoints {
    struct Create: Endpoint {
        typealias Response = VaultStatusResponse
        var path: String { "/v1/vault/create" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { VaultCreateRequest() }
    }

    struct Status: Endpoint {
        typealias Response = VaultStatusResponse
        var path: String { "/v1/vault/status" }
        var method: HTTPMethod { .get }
    }

    // MARK: - HER-105

    /// Paginated vault file list with optional space slug, filename
    /// substring (`q`), and createdAt cursor.
    struct ListFiles: Endpoint {
        typealias Response = VaultFileListResponse
        let spaceSlug: String?
        let q: String?
        let before: Date?
        let after: Date?
        let limit: Int?

        var path: String {
            var items: [URLQueryItem] = []
            if let spaceSlug, !spaceSlug.isEmpty { items.append(.init(name: "space", value: spaceSlug)) }
            if let q, !q.isEmpty { items.append(.init(name: "q", value: q)) }
            if let before { items.append(.init(name: "before", value: ISO8601DateFormatter().string(from: before))) }
            if let after { items.append(.init(name: "after", value: ISO8601DateFormatter().string(from: after))) }
            if let limit { items.append(.init(name: "limit", value: String(limit))) }
            var comps = URLComponents()
            comps.path = "/v1/vault/files"
            if !items.isEmpty { comps.queryItems = items }
            return comps.string ?? "/v1/vault/files"
        }
        var method: HTTPMethod { .get }
    }

    struct DeleteFile: Endpoint {
        typealias Response = EmptyResponse
        let relativePath: String
        let idempotencyKey: UUID?
        init(relativePath: String, idempotencyKey: UUID? = nil) {
            self.relativePath = relativePath
            self.idempotencyKey = idempotencyKey
        }
        var path: String {
            "/v1/vault/files/\(Self.escape(relativePath))"
        }
        var method: HTTPMethod { .delete }

        static func escape(_ raw: String) -> String {
            raw.split(separator: "/").map {
                $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
            }.joined(separator: "/")
        }
    }

    struct MoveFile: Endpoint {
        typealias Response = VaultFileDTO
        let from: String
        let to: String
        let idempotencyKey: UUID?
        init(from: String, to: String, idempotencyKey: UUID? = nil) {
            self.from = from
            self.to = to
            self.idempotencyKey = idempotencyKey
        }
        var path: String { "/v1/vault/files/move" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { VaultMoveRequest(path: from, newPath: to) }
        var encoder: JSONEncoder {
            let e = JSONEncoder()
            e.keyEncodingStrategy = .convertToSnakeCase
            return e
        }
    }
}
