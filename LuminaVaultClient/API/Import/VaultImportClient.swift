// LuminaVaultClient/LuminaVaultClient/API/Import/VaultImportClient.swift

import Foundation

protocol VaultImportClientProtocol: Sendable {
    func bulk(space: String, files: [VaultBulkFile], onConflict: String?) async throws -> VaultBulkResponse
    /// E7.4: `POST /v1/vault/import/notion`. `zipFile` is a Notion export on
    /// disk, streamed as the raw body and never loaded into memory. A dry run
    /// writes nothing and returns the same report. `onUploadProgress` gets the
    /// fraction of the file sent, 0...1, off the main actor; at 1 the server
    /// has the file and is working on it.
    func importNotion(
        zipFile: URL,
        space: String,
        dryRun: Bool,
        onConflict: String,
        onUploadProgress: (@Sendable (Double) -> Void)?
    ) async throws -> VaultNotionImportReport
}

extension VaultImportClientProtocol {
    /// Fakes that only script the folder import get an error from the Notion
    /// route rather than a compile error; `VaultImportHTTPClient` implements it.
    func importNotion(
        zipFile _: URL,
        space _: String,
        dryRun _: Bool,
        onConflict _: String,
        onUploadProgress _: (@Sendable (Double) -> Void)?
    ) async throws -> VaultNotionImportReport {
        throw URLError(.unsupportedURL)
    }
}

struct VaultImportHTTPClient: VaultImportClientProtocol {
    let client: BaseHTTPClient

    func bulk(space: String, files: [VaultBulkFile], onConflict: String?) async throws -> VaultBulkResponse {
        try await client.execute(
            VaultImportEndpoints.Bulk(request: VaultBulkRequest(space: space, files: files, onConflict: onConflict)),
        )
    }

    /// The server answers only after the whole import, and it embeds every
    /// note inside the request, so the wait after the upload can run to
    /// minutes. This is the request's idle timeout, for this route only.
    nonisolated static let notionImportTimeout: TimeInterval = 15 * 60
    nonisolated static let notionContentType = "application/zip"

    func importNotion(
        zipFile: URL,
        space: String,
        dryRun: Bool,
        onConflict: String,
        onUploadProgress: (@Sendable (Double) -> Void)?
    ) async throws -> VaultNotionImportReport {
        let raw = try await client.uploadFile(
            path: Self.notionImportPath(space: space, dryRun: dryRun, onConflict: onConflict),
            method: .post,
            fileURL: zipFile,
            contentType: Self.notionContentType,
            timeout: Self.notionImportTimeout,
            onProgress: onUploadProgress,
        )
        do {
            return try JSONDecoder.hvDefault.decode(VaultNotionImportReport.self, from: raw)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    /// The request `importNotion` sends, without its body; for tests.
    func notionImportRequest(space: String, dryRun: Bool, onConflict: String) async throws -> URLRequest {
        try await client.uploadFileRequest(
            path: Self.notionImportPath(space: space, dryRun: dryRun, onConflict: onConflict),
            method: .post,
            contentType: Self.notionContentType,
            timeout: Self.notionImportTimeout,
        )
    }

    /// `/v1/vault/import/notion?space=&dryRun=&onConflict=`.
    nonisolated static func notionImportPath(space: String, dryRun: Bool, onConflict: String) -> String {
        let fallback = "/v1/vault/import/notion"
        var comps = URLComponents()
        comps.path = fallback
        comps.queryItems = [
            URLQueryItem(name: "space", value: space),
            URLQueryItem(name: "dryRun", value: dryRun ? "true" : "false"),
            URLQueryItem(name: "onConflict", value: onConflict),
        ]
        // URLComponents leaves "+" alone, and a query parser reads it as a
        // space: "C++ notes" would arrive as "C   notes".
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return comps.string ?? fallback
    }
}
