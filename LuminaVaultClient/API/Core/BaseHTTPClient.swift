// LuminaVaultClient/LuminaVaultClient/API/Core/BaseHTTPClient.swift
import Foundation
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "http")

private extension Encodable {
    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

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
            do { req.httpBody = try body.encoded() }
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
}
