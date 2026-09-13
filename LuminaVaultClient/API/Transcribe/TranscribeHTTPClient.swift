// LuminaVaultClient/LuminaVaultClient/API/Transcribe/TranscribeHTTPClient.swift
//
// The audio body goes up as raw bytes, exactly like a vault upload — the
// format is in the `Content-Type` header, not in a multipart part.

import Foundation

final class TranscribeHTTPClient: TranscribeClientProtocol {
    /// The server refuses anything larger, and a clip that is refused after a
    /// long upload on a phone connection is a bad way to find out. The
    /// recorder caps duration; this is the backstop for the byte count.
    static let maxBytes = 10 * 1024 * 1024

    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func transcribe(audio: Data, contentType: String) async throws -> TranscriptionResult {
        guard !audio.isEmpty, audio.count <= Self.maxBytes else {
            // 413 is what the server would answer; raising it here saves a
            // long upload on a phone connection just to be refused.
            throw APIError.httpError(statusCode: 413, data: Data())
        }

        let raw = try await client.uploadBytes(
            path: "/v1/transcribe",
            method: .post,
            body: audio,
            contentType: contentType,
        )
        return try JSONDecoder.hvDefault.decode(TranscriptionResult.self, from: raw)
    }
}
