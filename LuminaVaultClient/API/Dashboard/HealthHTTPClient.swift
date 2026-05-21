// LuminaVaultClient/LuminaVaultClient/API/Dashboard/HealthHTTPClient.swift
//
// HER-244 — GET /health readiness probe. Plaintext "ok" response, no
// JSON decode. Used by the Dashboard System Status card to flip
// online/offline within ~2s.

import Foundation

protocol HealthClientProtocol: Sendable {
    func isOnline() async -> Bool
}

final class HealthHTTPClient: HealthClientProtocol {
    private let session: URLSession
    private let timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 2.0) {
        self.session = session
        self.timeout = timeout
    }

    func isOnline() async -> Bool {
        guard let url = URL(string: "/health", relativeTo: Config.apiBaseURL) else {
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
