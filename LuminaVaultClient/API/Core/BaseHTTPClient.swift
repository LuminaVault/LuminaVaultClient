// LuminaVaultClient/LuminaVaultClient/API/Core/BaseHTTPClient.swift
import Foundation
import OSLog
import PostHog

private let log = Logger(subsystem: "com.luminavault", category: "http")

// (Per-endpoint encoders live on `Endpoint.encoder`. We intentionally do
// NOT use a shared `Encodable.encoded()` helper here so each call site
// can pick snake_case + ISO-8601 vs camelCase as it needs.)

final class BaseHTTPClient: Sendable {
    typealias TokenProvider = @Sendable () async -> String?
    typealias RefreshHandler = @Sendable () async throws -> String
    typealias AuthFailureHandler = @Sendable () async -> Void

    private let session: URLSession
    private let baseURL: URL
    private let tokenProvider: TokenProvider
    private let refreshHandler: RefreshHandler?
    private let onAuthFailure: AuthFailureHandler?
    private let refreshCoordinator: TokenRefreshCoordinator?

    init(
        baseURL: URL = Config.apiBaseURL,
        session: URLSession = .shared,
        tokenProvider: @escaping TokenProvider = { nil },
        refreshHandler: RefreshHandler? = nil,
        onAuthFailure: AuthFailureHandler? = nil,
        refreshCoordinator: TokenRefreshCoordinator? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.refreshHandler = refreshHandler
        self.onAuthFailure = onAuthFailure
        // HER-237: a refresh handler without a coordinator would stampede
        // the auth server on concurrent 401s. Always provide one when
        // refresh is wired; share it across clients to keep single-flight
        // semantics process-wide.
        self.refreshCoordinator = refreshHandler != nil
            ? (refreshCoordinator ?? TokenRefreshCoordinator())
            : nil
    }

    func execute<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        do {
            return try await executeOnce(endpoint)
        } catch APIError.unauthorized where shouldRetryAfterRefresh(endpoint: endpoint) {
            try await performRefreshOrSignOut()
            return try await executeOnce(endpoint)
        }
    }

    private func executeOnce<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        guard let url = URL(string: endpoint.path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if endpoint.requiresAuth, let token = await tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // HER-39: when the endpoint carries an idempotency key, send it
        // so the server replays a cached response on retry instead of
        // re-executing the handler.
        if let key = endpoint.idempotencyKey {
            req.setValue(key.uuidString, forHTTPHeaderField: "Idempotency-Key")
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
        requiresAuth: Bool = true,
        idempotencyKey: UUID? = nil
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
        if let idempotencyKey {
            req.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
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
        do {
            return try await fetchBytesOnce(path: path, method: method, requiresAuth: requiresAuth)
        } catch APIError.unauthorized where requiresAuth && refreshHandler != nil {
            try await performRefreshOrSignOut()
            return try await fetchBytesOnce(path: path, method: method, requiresAuth: requiresAuth)
        }
    }

    private func fetchBytesOnce(path: String, method: HTTPMethod, requiresAuth: Bool) async throws -> (Data, String) {
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

    private func shouldRetryAfterRefresh<E: Endpoint>(endpoint: E) -> Bool {
        guard refreshHandler != nil, !endpoint.skipsAuthRefresh else { return false }
        return true
    }

    private func performRefreshOrSignOut() async throws {
        guard let coordinator = refreshCoordinator, let refreshHandler else {
            throw APIError.unauthorized
        }
        do {
            _ = try await coordinator.refresh(using: refreshHandler)
            PostHogSDK.shared.capture("auth_token_refresh_success")
        } catch {
            PostHogSDK.shared.capture("auth_token_refresh_failure")
            await onAuthFailure?()
            throw APIError.unauthorized
        }
    }
}
