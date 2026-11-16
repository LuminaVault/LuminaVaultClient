// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultEndpoints.swift
// HER-35: POST /v1/vault/create + GET /v1/vault/status.
// HER-105: GET /v1/vault/files (list with space/q/before/after/limit),
//          POST /v1/vault/files/move, DELETE /v1/vault/files/{path}.
// Note: GET /v1/vault/files/{path} (raw bytes) is *not* expressed here
// as an Endpoint because it returns binary rather than JSON; the read
// path lives directly on `VaultHTTPClient.readFile` via
// `BaseHTTPClient.fetchBytes`.
import Foundation

nonisolated enum VaultEndpoints {
    nonisolated struct Create: Endpoint {
        typealias Response = VaultStatusResponse
        var path: String { "/v1/vault/create" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { VaultCreateRequest() }
    }

    nonisolated struct Status: Endpoint {
        typealias Response = VaultStatusResponse
        var path: String { "/v1/vault/status" }
        var method: HTTPMethod { .get }
    }

    // MARK: - HER-105

    /// Paginated vault file list with optional space slug, filename
    /// substring (`q`), and createdAt cursor.
    nonisolated struct ListFiles: Endpoint {
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

    /// Backlog E2.2 — a note's wikilinks, outgoing and incoming (backlinks).
    nonisolated struct DocumentLinks: Endpoint {
        typealias Response = VaultLinksResponse
        let vaultFileID: UUID
        var path: String { "/v1/vault/links/\(vaultFileID.uuidString.lowercased())" }
        var method: HTTPMethod { .get }
    }

    // Backlog E3.4: the trash. Ids go lowercase into the path, as DocumentLinks.
    nonisolated struct TrashList: Endpoint {
        typealias Response = VaultTrashListResponse
        var path: String { "/v1/vault/trash" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct TrashRestore: Endpoint {
        typealias Response = VaultFileDTO
        let id: UUID
        var path: String { "/v1/vault/trash/\(id.uuidString.lowercased())/restore" }
        var method: HTTPMethod { .post }
    }

    nonisolated struct TrashDelete: Endpoint {
        typealias Response = EmptyResponse
        let id: UUID
        var path: String { "/v1/vault/trash/\(id.uuidString.lowercased())" }
        var method: HTTPMethod { .delete }
    }

    // Backlog E4.5: version history (server E4.3). `sha` is hex, safe in a path.
    nonisolated struct History: Endpoint {
        typealias Response = VaultHistoryResponse
        let filePath: String
        let limit: Int?
        let before: String?
        var path: String {
            var items = [URLQueryItem(name: "path", value: filePath)]
            if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
            if let before, !before.isEmpty { items.append(URLQueryItem(name: "before", value: before)) }
            return VaultEndpoints.withQuery("/v1/vault/history", items)
        }
        var method: HTTPMethod { .get }
        var presentsPaywallOn402: Bool { false }
    }

    /// Raw bytes of `filePath` at `sha`; read through `fetchBytes`, not `execute`.
    static func versionPath(sha: String, filePath: String) -> String {
        withQuery("/v1/vault/versions/\(sha)", [URLQueryItem(name: "path", value: filePath)])
    }

    nonisolated struct VersionRestore: Endpoint {
        typealias Response = VaultFileDTO
        let sha: String
        let filePath: String
        /// `NoteVersion.ifMatch` of the text on screen; nil skips the check.
        let ifMatch: String?
        var path: String {
            VaultEndpoints.withQuery("/v1/vault/versions/\(sha)/restore", [URLQueryItem(name: "path", value: filePath)])
        }
        var method: HTTPMethod { .post }
        var additionalHeaders: [String: String] {
            ifMatch.map { ["If-Match": $0] } ?? [:]
        }
    }

    /// `path?query`, with `+` escaped too: URLComponents leaves it alone and a
    /// server form-decoder would read it as a space.
    static func withQuery(_ path: String, _ items: [URLQueryItem]) -> String {
        var comps = URLComponents()
        comps.path = path
        comps.queryItems = items
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return comps.string ?? path
    }

    // Backlog E6.4: daily notes and templates.
    /// 201 when the note was created, 200 when it existed; same body either way.
    nonisolated struct DailyNote: Endpoint {
        typealias Response = VaultFileDTO
        let tz: String?
        var path: String {
            var comps = URLComponents()
            comps.path = "/v1/vault/daily"
            if let tz, !tz.isEmpty { comps.queryItems = [URLQueryItem(name: "tz", value: tz)] }
            return comps.string ?? "/v1/vault/daily"
        }
        var method: HTTPMethod { .post }
    }

    nonisolated struct TemplatesSeed: Endpoint {
        typealias Response = VaultTemplatesSeedResponse
        var path: String { "/v1/vault/templates/seed" }
        var method: HTTPMethod { .post }
    }

    nonisolated struct NoteFromTemplate: Endpoint {
        typealias Response = VaultFileDTO
        let request: VaultFromTemplateRequest
        var path: String { "/v1/vault/notes/from-template" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    nonisolated struct DeleteFile: Endpoint {
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

    nonisolated struct MoveFile: Endpoint {
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
        // Wire is camelCase: the server decodes `VaultMoveRequest{path,newPath}`
        // with its default decoder. A `.convertToSnakeCase` encoder here sent
        // `new_path` → 400 "Coding key `newPath` not found." on every move.
        var body: (any Encodable)? { VaultMoveRequest(path: from, newPath: to) }
    }
}
