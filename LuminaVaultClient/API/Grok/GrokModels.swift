// LuminaVaultClient/LuminaVaultClient/API/Grok/GrokModels.swift
//
// HER-240c — wire DTOs for `/v1/grok/*`. Server-local on the
// LuminaVaultServer side (HER-240c proxy); iOS mirrors locally. Both move
// to `LuminaVaultShared` once that package settles, per HER-213.

import Foundation

struct GrokChatMessage: Codable, Sendable, Equatable {
    let role: String
    let content: String
}

struct GrokChatRequest: Codable, Sendable {
    let messages: [GrokChatMessage]
    let model: String?
    let stream: Bool?
    let maxTokens: Int?
}

struct GrokUsage: Codable, Sendable, Equatable {
    let promptTokens: Int
    let completionTokens: Int
}

struct GrokChatResponse: Codable, Sendable, Equatable {
    let answer: String
    let model: String
    let usage: GrokUsage?
}

struct GrokXSearchRequest: Codable, Sendable {
    let query: String
    let allowedXHandles: [String]?
    let excludedXHandles: [String]?
    let fromDate: String?
    let toDate: String?
    let enableImageUnderstanding: Bool?
    let enableVideoUnderstanding: Bool?
}

struct GrokXSearchCitation: Codable, Sendable, Equatable, Identifiable {
    var id: String { url }
    let url: String
    let title: String?
    let publishedAt: Date?
}

struct GrokXSearchResponse: Codable, Sendable, Equatable {
    let answer: String
    let citations: [GrokXSearchCitation]
    let model: String
}

struct GrokVisionRequest: Codable, Sendable {
    let prompt: String
    let imageURLs: [String]
}

struct GrokVisionResponse: Codable, Sendable, Equatable {
    let answer: String
    let model: String
}

struct GrokTTSRequest: Codable, Sendable {
    let text: String
    let voice: String?
}

struct GrokTTSResponse: Codable, Sendable, Equatable {
    let audioBase64: String
    let mimeType: String
}
