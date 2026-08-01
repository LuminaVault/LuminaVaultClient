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
    /// Probes the *active* endpoint, so it must go through the same pinned
    /// session as every other API call. On `URLSession.shared` this probe kept
    /// reporting "online" while TLS pinning was cancelling every real request —
    /// the System Status card stayed green through a total outage.
    private let session: URLSession
    /// Unpinned session for `isReachable(baseURL:)`, which validates arbitrary
    /// user-entered BYO / Tailscale URLs that are not the managed host and are
    /// often self-signed.
    private let probeSession: URLSession
    private let timeout: TimeInterval

    init(
        session: URLSession = .lvPinned,
        probeSession: URLSession = .shared,
        timeout: TimeInterval = 2.0
    ) {
        self.session = session
        self.probeSession = probeSession
        self.timeout = timeout
    }

    func isOnline() async -> Bool {
        await probe(baseURL: Config.apiBaseURL, using: session)
    }

    /// Probes `GET <baseURL>/health` for a URL the user is about to adopt —
    /// the BYO / Tailscale server picker tests an endpoint *before* persisting
    /// it as active. Deliberately unpinned: the host is not the managed host.
    func isReachable(baseURL: URL) async -> Bool {
        await probe(baseURL: baseURL, using: probeSession)
    }

    private func probe(baseURL: URL, using session: URLSession) async -> Bool {
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
