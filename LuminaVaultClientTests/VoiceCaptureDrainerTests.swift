// LuminaVaultClient/LuminaVaultClientTests/VoiceCaptureDrainerTests.swift
//
// A queued voice note becomes a transcript in the vault.
//
// Recording goes through the capture queue rather than transcribing inline, so
// a note can be spoken with no signal and transcribed whenever the device next
// has one. What matters here is the shape of that hand-off: the audio reaches
// the transcription endpoint, the *transcript* — not the audio — is what lands
// in the vault, and a clip that turns out to be silence does not leave an empty
// note behind.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

final class VoiceCaptureDrainerTests: XCTestCase {
    private func makeRow(
        id: UUID = UUID(),
        audio: Data = Data("fake-m4a-bytes".utf8),
        contentType: String = "audio/mp4"
    ) -> CaptureRowSnapshot {
        CaptureRowSnapshot(
            id: id,
            createdAt: .now,
            captionText: nil,
            imageData: audio,
            contentType: contentType,
            fileExtension: "m4a",
            lat: nil,
            lng: nil,
            accuracyM: nil,
            placeName: nil,
            spaceID: nil,
            kind: .voice,
            urlString: nil,
            attempts: 0
        )
    }

    func testAudioIsTranscribedAndTheTranscriptStored() async throws {
        let row = makeRow()
        let queue = SingleRowQueue(rows: [row])
        let uploader = RecordingUploader()
        let transcriber = StubTranscriber(text: "remember to renew the domain")
        let drainer = CaptureDrainer(
            queue: queue,
            vaultUploader: uploader,
            memoryClient: InertMemoryClient(),
            transcribeClient: transcriber
        )

        await drainer.tick()

        let sent = await transcriber.received
        XCTAssertEqual(sent?.contentType, "audio/mp4", "the server dispatches on the declared MIME")
        XCTAssertEqual(sent?.audio, row.imageData)

        let notes = await uploader.notes
        XCTAssertEqual(notes.count, 1)
        let note = try XCTUnwrap(notes.first)
        XCTAssertEqual(String(decoding: note.data, as: UTF8.self), "remember to renew the domain")
        XCTAssertEqual(note.contentType, "text/markdown", "a voice note is stored as an ordinary note")
        XCTAssertTrue(note.relativePath.hasSuffix("\(row.id.uuidString).md"))

        let assets = await uploader.assets
        XCTAssertTrue(assets.isEmpty, "the audio itself must not be uploaded to the vault")
    }

    func testSilenceIsDroppedRatherThanStoredAsAnEmptyNote() async throws {
        let row = makeRow()
        let queue = SingleRowQueue(rows: [row])
        let uploader = RecordingUploader()
        let drainer = CaptureDrainer(
            queue: queue,
            vaultUploader: uploader,
            memoryClient: InertMemoryClient(),
            transcribeClient: StubTranscriber(text: "   \n  ")
        )

        await drainer.tick()

        let notes = await uploader.notes
        XCTAssertTrue(notes.isEmpty, "an empty note is worse than no note")
        let deleted = await queue.deleted
        XCTAssertEqual(deleted, [row.id], "a clip with no speech must not be retried forever")
    }

    func testAVoiceRowIsDroppedWhenNoTranscriberIsConfigured() async {
        let row = makeRow()
        let queue = SingleRowQueue(rows: [row])
        let drainer = CaptureDrainer(
            queue: queue,
            vaultUploader: RecordingUploader(),
            memoryClient: InertMemoryClient(),
            transcribeClient: nil
        )

        await drainer.tick()

        let deleted = await queue.deleted
        XCTAssertEqual(deleted, [row.id])
    }

    func testATranscriptionFailureIsRecordedForRetry() async {
        struct Boom: Error {}
        let row = makeRow()
        let queue = SingleRowQueue(rows: [row])
        let drainer = CaptureDrainer(
            queue: queue,
            vaultUploader: RecordingUploader(),
            memoryClient: InertMemoryClient(),
            transcribeClient: StubTranscriber(error: Boom())
        )

        await drainer.tick()

        let failures = await queue.failures
        XCTAssertEqual(failures.count, 1, "a transient failure is a retry, not a discard")
        let deleted = await queue.deleted
        XCTAssertTrue(deleted.isEmpty, "the recording must survive to be retried")
    }
}

// MARK: - Stubs

private actor SingleRowQueue: CaptureQueueProtocol {
    private var rows: [CaptureRowSnapshot]
    private(set) var deleted: [UUID] = []
    private(set) var failures: [(id: UUID, error: String)] = []

    init(rows: [CaptureRowSnapshot]) { self.rows = rows }

    func enqueue(_: CaptureSnapshot) async throws {}
    func pending() async throws -> [CaptureRowSnapshot] { rows }
    func delete(id: UUID) async throws {
        deleted.append(id)
        rows.removeAll { $0.id == id }
    }
    func markFailure(id: UUID, error: String, flipToFailed _: Bool) async throws {
        failures.append((id, error))
    }
    func count() async throws -> Int { rows.count }
}

private actor StubTranscriber: TranscribeClientProtocol {
    struct Call: Sendable, Equatable {
        let audio: Data
        let contentType: String
    }

    private let text: String?
    private let error: Error?
    private(set) var received: Call?

    init(text: String) { self.text = text; self.error = nil }
    init(error: Error) { self.text = nil; self.error = error }

    func transcribe(audio: Data, contentType: String) async throws -> TranscriptionResult {
        received = Call(audio: audio, contentType: contentType)
        if let error { throw error }
        return TranscriptionResult(
            id: "t1",
            text: text ?? "",
            language: "en",
            confidence: 0.9,
            durationSeconds: 2
        )
    }
}

private actor RecordingUploader: VaultUploadClientProtocol {
    struct Upload: Sendable {
        let data: Data
        let contentType: String
        let relativePath: String
    }

    private(set) var assets: [Upload] = []
    private(set) var notes: [Upload] = []

    func uploadAsset(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID _: UUID?
    ) async throws -> VaultUploadResponse {
        assets.append(Upload(data: data, contentType: contentType, relativePath: relativePath))
        return VaultUploadResponse(path: relativePath, size: data.count, contentType: contentType, sha256: "")
    }

    func uploadNote(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID _: UUID?,
        metadata _: VaultNoteMetadataDTO?
    ) async throws -> VaultUploadResponse {
        notes.append(Upload(data: data, contentType: contentType, relativePath: relativePath))
        return VaultUploadResponse(path: relativePath, size: data.count, contentType: contentType, sha256: "")
    }
}

/// The voice path never touches memory — the server owns the note's memory via
/// `uploadNote(?note=true)`. Everything here throws so a stray call is loud
/// rather than quietly satisfied. Mirrors `StubMemoryClient` in the chat tests.
private final class InertMemoryClient: MemoryClientProtocol, Sendable {
    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func get(id _: UUID) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse {
        throw APIError.unauthorized
    }

    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse {
        throw APIError.unauthorized
    }

    func delete(id _: UUID) async throws {
        throw APIError.unauthorized
    }
}
