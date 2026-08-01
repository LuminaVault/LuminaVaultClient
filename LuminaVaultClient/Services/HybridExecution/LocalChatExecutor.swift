import Foundation
import LuminaVaultShared

protocol LocalChatExecuting: Sendable {
    var displayName: String { get }
    var modelID: String { get }
    func isAvailable() async -> Bool
    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, any Error>
}

enum LocalChatExecutorError: LocalizedError {
    case invalidEndpoint
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "The local model endpoint is invalid."
        case .unavailable: "The local model is unavailable."
        case .invalidResponse: "The local model returned an invalid response."
        }
    }
}

struct LocalEndpointConfiguration: Codable, Equatable, Sendable {
    let kind: LocalEndpointKind
    let baseURL: URL
    let model: String
    let apiKey: String?
}

struct LocalEndpointChatExecutor: LocalChatExecuting {
    let configuration: LocalEndpointConfiguration
    private let session: URLSession

    var displayName: String {
        switch configuration.kind {
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .mlxServer: "MLX"
        case .openAICompatible: "OpenAI-compatible server"
        }
    }

    var modelID: String {
        configuration.model
    }

    init(configuration: LocalEndpointConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func isAvailable() async -> Bool {
        let path = configuration.kind == .ollama ? "api/tags" : "v1/models"
        guard let url = URL(string: path, relativeTo: configuration.baseURL) else { return false }
        var request = URLRequest(url: url)
        if let key = configuration.apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 3
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        guard (200 ..< 300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        let models: [String]
        if configuration.kind == .ollama {
            models = (object["models"] as? [[String: Any]] ?? []).flatMap { item in
                [item["name"] as? String, item["model"] as? String].compactMap(\.self)
            }
        } else {
            models = (object["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        }
        return models.contains(configuration.model)
    }

    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let ollama = configuration.kind == .ollama
                    let path = ollama ? "api/chat" : "v1/chat/completions"
                    guard let url = URL(string: path, relativeTo: configuration.baseURL) else {
                        throw LocalChatExecutorError.invalidEndpoint
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let key = configuration.apiKey {
                        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": configuration.model,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "stream": true,
                    ])
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                        throw LocalChatExecutorError.unavailable
                    }
                    // Frame at the byte level via the shared `SSEFrameParser`,
                    // the same path `BaseHTTPClient` uses.
                    //
                    // This loop used to read `bytes.lines`. `AsyncLineSequence`
                    // silently drops empty lines — and empty lines are exactly
                    // what delimits SSE frames — so multi-frame responses got
                    // concatenated and failed to decode. `BaseHTTPClient` was
                    // fixed for this long ago and documents it at its call
                    // site; local/hybrid streaming never got the same fix.
                    var parser = SSEFrameParser()

                    func emit(_ data: Data) {
                        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { return }
                        let delta: String? = if ollama {
                            (object["message"] as? [String: Any])?["content"] as? String
                        } else {
                            (((object["choices"] as? [[String: Any]])?.first)?["delta"] as? [String: Any])?["content"] as? String
                        }
                        if let delta, !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }

                    outer: for try await byte in bytes {
                        if Task.isCancelled { break }
                        for outcome in parser.feed(bytes: CollectionOfOne(byte)) {
                            switch outcome {
                            case .pending: continue
                            case .event(let data): emit(data)
                            case .done: break outer
                            }
                        }
                    }
                    // Drain a trailing partial line + any buffered frame so the
                    // final token is never dropped.
                    for outcome in parser.finishBytes() {
                        switch outcome {
                        case .pending: continue
                        case .event(let data): emit(data)
                        case .done: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
