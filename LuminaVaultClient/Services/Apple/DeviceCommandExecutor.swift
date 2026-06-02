// LuminaVaultClient/LuminaVaultClient/Services/Apple/DeviceCommandExecutor.swift
//
// Apple Integration P0b (client) — the always-on device-RPC executor. Holds a
// persistent WebSocket to the tenant broadcast channel (/v1/ws), decodes
// `device_command` envelopes the server sends (via DeviceCommandBroker),
// executes them against the device, and POSTs the result to
// /v1/devices/command/{id}/result (resolving the server's pending request).
//
// Reconnects with a fixed backoff while running. Started by AppState once the
// user is authenticated; cancelled on sign-out. First handler is `ping`
// (round-trip proof); Apple handlers (reminder_create, …) plug into `handle`.

import Foundation
import LuminaVaultShared
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "apple.device-rpc")

enum DeviceCommandEndpoints {
    struct PostResult: Endpoint {
        typealias Response = EmptyResponse
        let result: DeviceCommandResult
        var path: String { "/v1/devices/command/\(result.id.uuidString)/result" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { result }
    }
}

actor DeviceCommandExecutor {
    private let baseURL: URL
    private let tokenProvider: @Sendable () async -> String?
    private let httpClient: BaseHTTPClient
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var runTask: Task<Void, Never>?
    private let decoder = JSONDecoder()

    init(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
        httpClient: BaseHTTPClient,
        session: URLSession = .shared,
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.httpClient = httpClient
        self.session = session
    }

    func start() {
        guard runTask == nil else { return }
        runTask = Task { await self.runLoop() }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await connectAndPump()
            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(5)) // reconnect backoff
        }
    }

    private func connectAndPump() async {
        guard let url = wsURL() else { return }
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
                let text: String? = switch message {
                case .string(let t): t
                case .data(let d): String(data: d, encoding: .utf8)
                @unknown default: nil
                }
                if let text,
                   let data = text.data(using: .utf8),
                   let envelope = try? decoder.decode(DeviceCommandEnvelope.self, from: data),
                   envelope.type == "device_command"
                {
                    await handle(envelope.command)
                }
                // Non-matching frames (other features on /v1/ws) are ignored.
            } catch {
                log.warning("device-rpc ws receive failed: \(String(describing: error))")
                break
            }
        }
        task = nil
    }

    private func handle(_ command: DeviceCommand) async {
        let result: DeviceCommandResult
        switch command.kind {
        case .ping:
            result = DeviceCommandResult(id: command.id, ok: true, payload: ["pong": "1"])
        case .reminderCreate, .calendarCreate, .deviceFetch, .photoAnalyze:
            // Apple-SDK handlers land in P2+. Until then, report unsupported so
            // the server's pending request resolves instead of timing out.
            result = DeviceCommandResult(id: command.id, ok: false, error: "command \(command.kind.rawValue) not yet supported on this device")
        }
        do {
            _ = try await httpClient.execute(DeviceCommandEndpoints.PostResult(result: result))
        } catch {
            log.warning("device-rpc result post failed id=\(command.id.uuidString): \(String(describing: error))")
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
