// LuminaVaultClient/LuminaVaultClient/API/Core/BaseHTTPClient.swift
import Foundation
import LuminaVaultShared
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
    /// HER-211 — fired on every 402 response, regardless of whether the
    /// call site catches `APIError.paymentRequired`. The throw still
    /// happens (so HER-188 `EntitlementGate` reactive handling keeps
    /// working). `AppState` wires this to a root-level paywall sheet so
    /// the user sees the paywall even when no in-tree gate wraps the
    /// failing call site.
    typealias PaymentRequiredHandler = @Sendable (
        _ paywallID: String?,
        _ requiredTier: UserTier?
    ) async -> Void

    private let session: URLSession
    private var baseURL: URL { Config.apiBaseURL }
    private let tokenProvider: TokenProvider
    private let refreshHandler: RefreshHandler?
    private let onAuthFailure: AuthFailureHandler?
    private let onPaymentRequired: PaymentRequiredHandler?
    private let refreshCoordinator: TokenRefreshCoordinator?

    init(
        session: URLSession = .shared,
        tokenProvider: @escaping TokenProvider = { nil },
        refreshHandler: RefreshHandler? = nil,
        onAuthFailure: AuthFailureHandler? = nil,
        onPaymentRequired: PaymentRequiredHandler? = nil,
        refreshCoordinator: TokenRefreshCoordinator? = nil
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
        self.refreshHandler = refreshHandler
        self.onAuthFailure = onAuthFailure
        self.onPaymentRequired = onPaymentRequired
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
        // HER-330: extra caller headers (e.g. X-Admin-Token). Applied last so
        // they can't overwrite Authorization (which was set above).
        for (name, value) in endpoint.additionalHeaders {
            req.setValue(value, forHTTPHeaderField: name)
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
            if http.statusCode == 402 {
                // HER-188 — best-effort parse of `{ "paywall_id": "...",
                // "required_tier": "pro" }`. Bare 402 still produces a
                // typed error so EntitlementGate can present a paywall.
                let hints = try? JSONDecoder.hvDefault.decode(PaymentRequiredBody.self, from: data)
                // HER-211 — fire the universal interceptor BEFORE throwing.
                // AppState wires this to a root-level sheet; the throw
                // keeps HER-188's reactive EntitlementGate handlers working.
                await onPaymentRequired?(hints?.paywallID, hints?.requiredTier)
                throw APIError.paymentRequired(paywallID: hints?.paywallID, requiredTier: hints?.requiredTier)
            }
            if http.statusCode == 429 {
                // HER-194 — daily-cap / rate-limit surface. Parse the
                // seconds form of `Retry-After`; ignore HTTP-date form
                // (no current server endpoint emits it).
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw APIError.rateLimited(retryAfter: retryAfter)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpError(statusCode: http.statusCode, data: data)
            }
        }
        // HER-214 — 204 No Content (and any 2xx with an empty body) is
        // valid for endpoints typed as `EmptyResponse`-style structs.
        // Substitute `{}` so the decoder round-trips an empty value
        // instead of throwing "Unexpected end of file".
        let payload = data.isEmpty ? Data("{}".utf8) : data
        do { return try endpoint.decoder.decode(E.Response.self, from: payload) }
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
        idempotencyKey: UUID? = nil,
        extraHeaders: [String: String] = [:]
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
        for (k, v) in extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
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
            if http.statusCode == 402 {
                // HER-188 — best-effort parse of `{ "paywall_id": "...",
                // "required_tier": "pro" }`. Bare 402 still produces a
                // typed error so EntitlementGate can present a paywall.
                let hints = try? JSONDecoder.hvDefault.decode(PaymentRequiredBody.self, from: data)
                // HER-211 — fire the universal interceptor BEFORE throwing.
                // AppState wires this to a root-level sheet; the throw
                // keeps HER-188's reactive EntitlementGate handlers working.
                await onPaymentRequired?(hints?.paywallID, hints?.requiredTier)
                throw APIError.paymentRequired(paywallID: hints?.paywallID, requiredTier: hints?.requiredTier)
            }
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
            if http.statusCode == 402 {
                // HER-188 — best-effort parse of `{ "paywall_id": "...",
                // "required_tier": "pro" }`. Bare 402 still produces a
                // typed error so EntitlementGate can present a paywall.
                let hints = try? JSONDecoder.hvDefault.decode(PaymentRequiredBody.self, from: data)
                // HER-211 — fire the universal interceptor BEFORE throwing.
                // AppState wires this to a root-level sheet; the throw
                // keeps HER-188's reactive EntitlementGate handlers working.
                await onPaymentRequired?(hints?.paywallID, hints?.requiredTier)
                throw APIError.paymentRequired(paywallID: hints?.paywallID, requiredTier: hints?.requiredTier)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpError(statusCode: http.statusCode, data: data)
            }
            if let ct = http.value(forHTTPHeaderField: "Content-Type") {
                contentType = ct
            }
        }
        return (data, contentType)
    }

    /// HER-269 — Server-Sent Events transport. Returns an
    /// `AsyncThrowingStream` of `Event` values, one per SSE `data:` frame.
    /// The underlying URLSession task is cancelled when the consumer
    /// stops iterating (via `continuation.onTermination`), which lets
    /// SwiftUI `.task { }` modifiers tear down mid-stream when the view
    /// disappears.
    ///
    /// 401 handling: the response status is checked before the byte loop
    /// starts. On 401 the stream throws `APIError.unauthorized`; use
    /// `executeStreamWithRefresh` for the variant that retries once after
    /// a single-flight token refresh. Mid-stream 401s cannot be
    /// transparently retried (bytes already delivered) and propagate to
    /// the consumer unchanged.
    func executeStream<E: StreamingEndpoint>(_ endpoint: E) -> AsyncThrowingStream<E.Event, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [session, baseURL, tokenProvider] in
                do {
                    let request = try await Self.buildStreamRequest(
                        endpoint: endpoint,
                        baseURL: baseURL,
                        tokenProvider: tokenProvider,
                    )
                    log.debug("→ \(endpoint.method.rawValue) \(endpoint.path) [stream]")
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse {
                        log.debug("← \(http.statusCode) \(endpoint.path) [stream]")
                        if http.statusCode == 401 { throw APIError.unauthorized }
                        guard (200..<300).contains(http.statusCode) else {
                            var trailing = Data()
                            for try await byte in bytes { trailing.append(byte) }
                            throw APIError.httpError(statusCode: http.statusCode, data: trailing)
                        }
                    }

                    var parser = SSEFrameParser()

                    // Decode one frame and forward it. Wraps the decoder
                    // error so consumers see a typed `APIError`.
                    func emit(_ data: Data) throws {
                        let event: E.Event
                        do { event = try endpoint.decoder.decode(E.Event.self, from: data) }
                        catch { throw APIError.decodingFailed(error) }
                        continuation.yield(event)
                    }

                    // Frame the SSE stream at the byte level. We deliberately
                    // do NOT use `bytes.lines`: `AsyncLineSequence` drops the
                    // blank lines that delimit SSE frames, which made the
                    // parser concatenate the whole stream into one buffer and
                    // fail to decode ("Unexpected character '{' after
                    // top-level value").
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        for outcome in parser.feed(bytes: CollectionOfOne(byte)) {
                            switch outcome {
                            case .pending: continue
                            case .event(let data): try emit(data)
                            case .done: continuation.finish(); return
                            }
                        }
                    }
                    // Drain trailing partial line + buffered frame.
                    for outcome in parser.finishBytes() {
                        switch outcome {
                        case .pending: continue
                        case .event(let data): try emit(data)
                        case .done: continuation.finish(); return
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Same as `executeStream` but transparently retries once after a
    /// single-flight token refresh if the first connect attempt returns
    /// 401. Mid-stream 401s still propagate unchanged.
    func executeStreamWithRefresh<E: StreamingEndpoint>(_ endpoint: E) -> AsyncThrowingStream<E.Event, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                var didRefresh = false
                while !Task.isCancelled {
                    do {
                        for try await event in self.executeStream(endpoint) {
                            continuation.yield(event)
                        }
                        continuation.finish()
                        return
                    } catch APIError.unauthorized where !didRefresh && self.shouldRetryAfterRefresh(streamEndpoint: endpoint) {
                        didRefresh = true
                        do { try await self.performRefreshOrSignOut() }
                        catch { continuation.finish(throwing: error); return }
                        continue
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func buildStreamRequest<E: StreamingEndpoint>(
        endpoint: E,
        baseURL: URL,
        tokenProvider: TokenProvider,
    ) async throws -> URLRequest {
        guard let url = URL(string: endpoint.path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method.rawValue
        // SSE streams (LLM token streams) can be slow to emit their first
        // byte; raise the per-request timeout above the URLSession default
        // so a cold managed brain doesn't trip `URLError.timedOut`.
        req.timeoutInterval = endpoint.streamTimeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if endpoint.requiresAuth, let token = await tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // HER-330: extra caller headers (e.g. X-Admin-Token) for streams.
        for (name, value) in endpoint.additionalHeaders {
            req.setValue(value, forHTTPHeaderField: name)
        }
        if let body = endpoint.body {
            do { req.httpBody = try endpoint.encoder.encode(AnyEncodable(body)) }
            catch { throw APIError.encodingFailed(error) }
        }
        return req
    }

    private func shouldRetryAfterRefresh<E: Endpoint>(endpoint: E) -> Bool {
        guard refreshHandler != nil, !endpoint.skipsAuthRefresh else { return false }
        return true
    }

    private func shouldRetryAfterRefresh<E: StreamingEndpoint>(streamEndpoint: E) -> Bool {
        guard refreshHandler != nil, streamEndpoint.requiresAuth else { return false }
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
