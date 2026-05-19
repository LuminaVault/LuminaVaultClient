// LuminaVaultClient/LuminaVaultClient/API/Grok/GrokClientProtocol.swift
//
// HER-240c — `/v1/grok/*` client surface.

import Foundation

protocol GrokClientProtocol: Sendable {
    func chat(_ request: GrokChatRequest) async throws -> GrokChatResponse
    func xSearch(_ request: GrokXSearchRequest) async throws -> GrokXSearchResponse
    func vision(_ request: GrokVisionRequest) async throws -> GrokVisionResponse
    func tts(_ request: GrokTTSRequest) async throws -> GrokTTSResponse
}

final class GrokHTTPClient: GrokClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func chat(_ request: GrokChatRequest) async throws -> GrokChatResponse {
        try await client.execute(GrokEndpoints.Chat(request: request))
    }

    func xSearch(_ request: GrokXSearchRequest) async throws -> GrokXSearchResponse {
        try await client.execute(GrokEndpoints.XSearch(request: request))
    }

    func vision(_ request: GrokVisionRequest) async throws -> GrokVisionResponse {
        try await client.execute(GrokEndpoints.Vision(request: request))
    }

    func tts(_ request: GrokTTSRequest) async throws -> GrokTTSResponse {
        try await client.execute(GrokEndpoints.TTS(request: request))
    }
}
