// LuminaVaultClient/LuminaVaultClient/API/Dashboard/HealthHTTPClient.swift
//
// HER-244 — GET /health readiness probe. Plaintext "ok" response, no
// JSON decode. Used by the Dashboard System Status card to flip
// online/offline within ~2s.

import Foundation

protocol HealthClientProtocol: Sendable {
    func isOnline() async -> Bool
    func isReachable(baseURL: URL) async -> Bool
}

final class HealthHTTPClient: HealthClientProtocol {
    private let session: URLSession
    private let timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 2.0) {
        self.session = session
        self.timeout = timeout
    }

    func isOnline() async -> Bool {
        await isReachable(baseURL: Config.apiBaseURL)
    }

    /// Probes `GET <baseURL>/health`. Used both by the System Status card
    /// (against the active base URL) and the BYO server picker, which tests
    /// a user-entered URL *before* persisting it as the active endpoint.
    func isReachable(baseURL: URL) async -> Bool {
        guard let url = URL(string: "/health", relativeTo: baseURL) else {
            return false
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        do {
            let (_, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
