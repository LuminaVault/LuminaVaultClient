// LuminaVaultClient/LuminaVaultClient/API/Transcribe/TranscribeClientProtocol.swift
//
// `POST /v1/transcribe` — raw audio in, text out.
//
// The response type is declared here rather than imported from
// LuminaVaultShared, which is the documented arrangement for this endpoint:
// `TranscribeResponse` and `TranscribeSegment` were added to Shared under
// HER-203 and pruned again in v0.11.0 per the wire-types-only boundary, with
// `LuminaVaultServer/Sources/App/LLM/Transcribe/TranscribeDTOs.swift` recording
// that "they now live server-side; the iOS client builds its own decoders".
// This is the exception to the DTOs-come-from-Shared rule, not a new copy of
// something Shared already has.
//
// Transcription runs on the cluster's own whisper service. The server picks the
// provider (`transcribe.provider`, defaulting to `openai_compatible` pointed at
// `whisper.horus.svc.cluster.local`), so the client only has to hand over the
// bytes and say what format they are in.

import Foundation

/// The decoded body of `POST /v1/transcribe`.
///
/// `durationSeconds` arrives as `duration_seconds`; `JSONDecoder.hvDefault`
/// converts it, so no explicit CodingKeys are needed here.
struct TranscriptionResult: Decodable, Sendable, Equatable {
    let id: String
    let text: String
    let language: String
    let confidence: Double
    let durationSeconds: Double
}

protocol TranscribeClientProtocol: Sendable {
    /// - Parameter contentType: the audio MIME, which the server validates
    ///   against its own allowlist. m4a is `audio/mp4`.
    func transcribe(audio: Data, contentType: String) async throws -> TranscriptionResult
}
