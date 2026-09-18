// LuminaVaultClient/LuminaVaultClient/API/HermesWorkspace/HermesWorkspaceClient.swift
//
// The agent's checkout, read-only: a file tree, what has changed in it, and
// the diff for one file.
//
// Every call proxies the tenant's Hermes through our server, so what this
// shows is what the agent is actually working from rather than a second
// opinion computed on the device.
//
// There is no write surface, and that is the design rather than an omission.
// The upstream API can stage, commit, push and open pull requests; none of it
// is reachable, and exposing it needs an auth scope, an audit trail and a
// confirmation step first.

import Foundation
import LuminaVaultShared

protocol HermesWorkspaceClientProtocol: Sendable {
    func status(path: String) async throws -> HermesWorkspaceStatusDTO
    func listing(path: String) async throws -> HermesWorkspaceListingDTO
    func file(path: String) async throws -> HermesWorkspaceFileDTO
    func diff(repoPath: String, file: String) async throws -> HermesWorkspaceDiffDTO
}

final class HermesWorkspaceHTTPClient: HermesWorkspaceClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func status(path: String) async throws -> HermesWorkspaceStatusDTO {
        try await client.execute(HermesWorkspaceEndpoints.Status(repoPath: path))
    }

    func listing(path: String) async throws -> HermesWorkspaceListingDTO {
        try await client.execute(HermesWorkspaceEndpoints.Listing(directory: path))
    }

    func file(path: String) async throws -> HermesWorkspaceFileDTO {
        try await client.execute(HermesWorkspaceEndpoints.File(filePath: path))
    }

    func diff(repoPath: String, file: String) async throws -> HermesWorkspaceDiffDTO {
        try await client.execute(HermesWorkspaceEndpoints.Diff(repoPath: repoPath, file: file))
    }
}

enum HermesWorkspaceEndpoints {
    /// Percent-encodes a query value. `.urlQueryAllowed` leaves `&` and `+`
    /// intact, which would split a path with either in it into two parameters
    /// and silently point the request somewhere else.
    static func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    struct Status: Endpoint {
        typealias Response = HermesWorkspaceStatusDTO
        /// Named `repoPath` rather than `path` because `Endpoint` already
        /// requires a `path` for the URL, and the two would collide.
        let repoPath: String
        var path: String { "/v1/hermes/workspace/status?path=\(HermesWorkspaceEndpoints.escape(repoPath))" }
        var method: HTTPMethod { .get }
    }

    struct Listing: Endpoint {
        typealias Response = HermesWorkspaceListingDTO
        let directory: String
        var path: String { "/v1/hermes/workspace/files?path=\(HermesWorkspaceEndpoints.escape(directory))" }
        var method: HTTPMethod { .get }
    }

    struct File: Endpoint {
        typealias Response = HermesWorkspaceFileDTO
        let filePath: String
        var path: String { "/v1/hermes/workspace/file?path=\(HermesWorkspaceEndpoints.escape(filePath))" }
        var method: HTTPMethod { .get }
    }

    struct Diff: Endpoint {
        typealias Response = HermesWorkspaceDiffDTO
        let repoPath: String
        let file: String
        var path: String {
            "/v1/hermes/workspace/diff?path=\(HermesWorkspaceEndpoints.escape(repoPath))"
                + "&file=\(HermesWorkspaceEndpoints.escape(file))"
        }

        var method: HTTPMethod { .get }
    }
}
