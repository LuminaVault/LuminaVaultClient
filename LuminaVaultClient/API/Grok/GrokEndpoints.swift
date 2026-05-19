// LuminaVaultClient/LuminaVaultClient/API/Grok/GrokEndpoints.swift
//
// HER-240c — endpoints for `/v1/grok/*`. snake_case wire format on the
// request side to mirror the OpenAI/Hermes chat shape upstream.

import Foundation

enum GrokEndpoints {
    static var snakeCaseEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }

    struct Chat: Endpoint {
        typealias Response = GrokChatResponse
        let body: (any Encodable)?
        let request: GrokChatRequest
        init(request: GrokChatRequest) {
            self.request = request
            self.body = request
        }
        var path: String { "/v1/grok/chat" }
        var method: HTTPMethod { .post }
        var encoder: JSONEncoder { GrokEndpoints.snakeCaseEncoder }
    }

    struct XSearch: Endpoint {
        typealias Response = GrokXSearchResponse
        let body: (any Encodable)?
        let request: GrokXSearchRequest
        init(request: GrokXSearchRequest) {
            self.request = request
            self.body = request
        }
        var path: String { "/v1/grok/x-search" }
        var method: HTTPMethod { .post }
        var encoder: JSONEncoder { GrokEndpoints.snakeCaseEncoder }
    }

    struct Vision: Endpoint {
        typealias Response = GrokVisionResponse
        let body: (any Encodable)?
        let request: GrokVisionRequest
        init(request: GrokVisionRequest) {
            self.request = request
            self.body = request
        }
        var path: String { "/v1/grok/vision" }
        var method: HTTPMethod { .post }
        var encoder: JSONEncoder { GrokEndpoints.snakeCaseEncoder }
    }

    struct TTS: Endpoint {
        typealias Response = GrokTTSResponse
        let body: (any Encodable)?
        let request: GrokTTSRequest
        init(request: GrokTTSRequest) {
            self.request = request
            self.body = request
        }
        var path: String { "/v1/grok/tts" }
        var method: HTTPMethod { .post }
        var encoder: JSONEncoder { GrokEndpoints.snakeCaseEncoder }
    }
}
