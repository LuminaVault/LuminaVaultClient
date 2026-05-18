// LuminaVaultClient/LuminaVaultClient/API/Core/BaseHTTPClient.swift
import Foundation
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "http")

// (Per-endpoint encoders live on `Endpoint.encoder`. We intentionally do
// NOT use a shared `Encodable.encoded()` helper here so each call site
// can pick snake_case + ISO-8601 vs camelCase as it needs.)

final class BaseHTTPClient: Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let tokenProvider: @Sendable () async -> String?

    init(
        baseURL: URL = Config.apiBaseURL,
        session: URLSession = .shared,
        tokenProvider: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func execute<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        guard let url = URL(string: endpoint.path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if endpoint.requiresAuth, let token = await tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = endpoint.body {
            do { req.httpBody = try endpoint.encoder.encode(AnyEncodable(body)) }
            catch { throw APIError.encodingFailed(error) }
        }

        log.debug("→ \(endpoint.method.rawValue) \(endpoint.path)")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.networkFailure(error) }

        if let http = response as? HTTPURLResponse {
            log.debug("← \(http.statusCode) \(endpoint.path)")
            if http.statusCode == 401 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpError(statusCode: http.statusCode, data: data)
            }
        }
        do { return try endpoint.decoder.decode(E.Response.self, from: data) }
        catch { throw APIError.decodingFailed(error) }
    }

    /// HER-34 — raw-body upload (HEIC/JPEG capture). Bypasses the
    /// Endpoint encoder pipeline because the request body is binary.
    /// Returns the raw response `Data` so the caller can decode the
    /// JSON envelope that the server emits.
    func uploadBytes(
        path: String,
        method: HTTPMethod = .post,
        body: Data,
        contentType: String,
        requiresAuth: Bool = true
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if requiresAuth, let token = await tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        log.debug("→ \(method.rawValue) \(path) [\(body.count)b upload]")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.networkFailure(error) }

        if let http = response as? HTTPURLResponse {
            log.debug("← \(http.statusCode) \(path) [upload]")
            if http.statusCode == 401 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpError(statusCode: http.statusCode, data: data)
            }
        }
        return data
    }

    /// HER-105 — fetch raw bytes (vault file read). Bypasses the Endpoint
    /// decoder pipeline because the response body is binary, not JSON.
    /// Returns the raw `Data` plus the response's `Content-Type` so the
    /// Markdown reader can short-circuit MIME sniffing.
    func fetchBytes(path: String, method: HTTPMethod = .get, requiresAuth: Bool = true) async throws -> (Data, String) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        if requiresAuth, let token = await tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        log.debug("→ \(method.rawValue) \(path) [bytes]")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.networkFailure(error) }

        var contentType = "application/octet-stream"
        if let http = response as? HTTPURLResponse {
            log.debug("← \(http.statusCode) \(path) [bytes]")
            if http.statusCode == 401 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpError(statusCode: http.statusCode, data: data)
            }
            if let ct = http.value(forHTTPHeaderField: "Content-Type") {
                contentType = ct
            }
        }
        return (data, contentType)
    }
}
