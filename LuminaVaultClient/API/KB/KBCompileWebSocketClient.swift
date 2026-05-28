// LuminaVaultClient/LuminaVaultClient/API/KB/KBCompileWebSocketClient.swift
// HER-108 — subscribes to /v1/ws and decodes KBCompileProgressEvent frames.
// Connection is short-lived: opened just before a kb-compile POST and
// torn down on completion/error so the WS doesn't hold the foreground task
// when the user isn't actively syncing.
import Foundation
import LuminaVaultShared
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "ws.kb-compile")

protocol KBCompileWebSocketClientProtocol: Sendable {
    /// Opens a per-tenant WS subscription and yields decoded events as they
    /// arrive. Caller `await`s on the stream; cancelling the parent task
    /// closes the underlying URLSessionWebSocketTask via `disconnect()`.
    func events() -> AsyncStream<KBCompileProgressEvent>
    /// Tears down the underlying WS connection. Safe to call multiple times.
    func disconnect() async
}

actor KBCompileWebSocketClient: KBCompileWebSocketClientProtocol {
    private let baseURL: URL
    private let tokenProvider: @Sendable () async -> String?
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
        session: URLSession = .shared,
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        self.decoder = d
    }

    nonisolated func events() -> AsyncStream<KBCompileProgressEvent> {
        AsyncStream { continuation in
            let task = Task {
                await openAndPump(continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.disconnect() }
            }
        }
    }

    func disconnect() async {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func openAndPump(continuation: AsyncStream<KBCompileProgressEvent>.Continuation) async {
        guard let url = wsURL() else {
            log.error("kb-compile ws: malformed base url")
            continuation.finish()
            return
        }
        let token = await tokenProvider()
        var req = URLRequest(url: url)
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let ws = session.webSocketTask(with: req)
        task = ws
        ws.resume()

        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    if let event = decode(text: text) {
                        continuation.yield(event)
                    }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8),
                       let event = decode(text: text)
                    {
                        continuation.yield(event)
                    }
                @unknown default:
                    break
                }
            } catch {
                log.warning("kb-compile ws receive failed: \(String(describing: error))")
                break
            }
        }
        continuation.finish()
        await disconnect()
    }

    private func decode(text: String) -> KBCompileProgressEvent? {
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            return try decoder.decode(KBCompileProgressEvent.self, from: data)
        } catch {
            // /v1/ws is a broadcast channel — non-kb-compile frames are
            // expected (other features may publish here). Silently skip
            // anything that doesn't match our envelope.
            return nil
        }
    }

    private func wsURL() -> URL? {
        guard var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        switch c.scheme {
        case "https": c.scheme = "wss"
        case "http": c.scheme = "ws"
        default: break
        }
        c.path += "/v1/ws"
        return c.url
    }
}
