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

final class LocalEndpointChatExecutor: LocalChatExecuting, @unchecked Sendable {
    let configuration: LocalEndpointConfiguration
    private let session: URLSession

    var displayName: String {
        configuration.kind == .ollama ? "Ollama" : "Local server"
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
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200 ..< 300).contains(http.statusCode)
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
                    for try await rawLine in bytes.lines {
                        if Task.isCancelled {
                            break
                        }
                        let line = rawLine.hasPrefix("data:") ? String(rawLine.dropFirst(5)).trimmingCharacters(in: .whitespaces) : rawLine
                        if line.isEmpty || line == "[DONE]" {
                            continue
                        }
                        guard let data = line.data(using: .utf8),
                              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        let delta: String? = if ollama {
                            (object["message"] as? [String: Any])?["content"] as? String
                        } else {
                            (((object["choices"] as? [[String: Any]])?.first)?["delta"] as? [String: Any])?["content"] as? String
                        }
                        if let delta, !delta.isEmpty {
                            continuation.yield(delta)
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
