// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockGrokClient.swift
//
// HER-240c — scripted `GrokClientProtocol` fake.

@testable import LuminaVaultClient
import Foundation

final class MockGrokClient: GrokClientProtocol, @unchecked Sendable {
    var chatResult: Result<GrokChatResponse, Error> = .success(.stub)
    var xSearchResult: Result<GrokXSearchResponse, Error> = .success(.stub)
    var visionResult: Result<GrokVisionResponse, Error> = .success(.stub)
    var ttsResult: Result<GrokTTSResponse, Error> = .success(.stub)

    private(set) var calls: [Call] = []
    enum Call: Equatable {
        case chat(GrokChatRequest)
        case xSearch(query: String)
        case vision(prompt: String, imageURLs: [String])
        case tts(text: String)
    }

    func chat(_ request: GrokChatRequest) async throws -> GrokChatResponse {
        calls.append(.chat(request))
        return try chatResult.get()
    }

    func xSearch(_ request: GrokXSearchRequest) async throws -> GrokXSearchResponse {
        calls.append(.xSearch(query: request.query))
        return try xSearchResult.get()
    }

    func vision(_ request: GrokVisionRequest) async throws -> GrokVisionResponse {
        calls.append(.vision(prompt: request.prompt, imageURLs: request.imageURLs))
        return try visionResult.get()
    }

    func tts(_ request: GrokTTSRequest) async throws -> GrokTTSResponse {
        calls.append(.tts(text: request.text))
        return try ttsResult.get()
    }
}

extension GrokChatRequest: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.messages == rhs.messages
            && lhs.model == rhs.model
            && lhs.stream == rhs.stream
            && lhs.maxTokens == rhs.maxTokens
    }
}

extension GrokChatResponse {
    static let stub = GrokChatResponse(
        answer: "stub answer",
        model: "grok-4.3",
        usage: GrokUsage(promptTokens: 1, completionTokens: 2),
    )
}

extension GrokXSearchResponse {
    static let stub = GrokXSearchResponse(
        answer: "stub x_search answer",
        citations: [GrokXSearchCitation(url: "https://x.com/example/status/1", title: "Example post", publishedAt: nil)],
        model: "grok-4.20-reasoning",
    )
}

extension GrokVisionResponse {
    static let stub = GrokVisionResponse(answer: "stub vision", model: "grok-4.3")
}

extension GrokTTSResponse {
    static let stub = GrokTTSResponse(audioBase64: "", mimeType: "audio/mpeg")
}
