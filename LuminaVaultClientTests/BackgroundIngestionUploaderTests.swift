import Foundation
@testable import LuminaVaultClient
import Testing

@MainActor
struct BackgroundIngestionUploaderTests {
    @Test
    func `persisted background job round trips relaunch state`() throws {
        let job = BackgroundIngestionUploader.Job(
            id: UUID(),
            batchID: UUID(),
            itemID: UUID(),
            stagedPath: "/tmp/staged-source.pdf",
            bookmark: Data([1, 2, 3]),
            size: 9_000_000,
            chunkSize: 8_000_000,
            offset: 8_000_000,
            phase: .completing,
            attempts: 2
        )

        let restored = try JSONDecoder().decode(
            BackgroundIngestionUploader.Job.self,
            from: JSONEncoder().encode(job)
        )

        #expect(restored.id == job.id)
        #expect(restored.batchID == job.batchID)
        #expect(restored.itemID == job.itemID)
        #expect(restored.bookmark == job.bookmark)
        #expect(restored.offset == job.offset)
        #expect(restored.phase == .completing)
        #expect(restored.attempts == 2)
    }

    @Test
    func `missing staged source without bookmark fails recovery`() {
        let job = BackgroundIngestionUploader.Job(
            id: UUID(),
            batchID: UUID(),
            itemID: UUID(),
            stagedPath: "/tmp/does-not-exist-\(UUID().uuidString)",
            bookmark: nil,
            size: 1,
            chunkSize: 1,
            offset: 0,
            phase: .chunks,
            attempts: 0
        )

        #expect(throws: CocoaError.self) {
            try BackgroundIngestionUploader.restoreStagedFileIfNeeded(job: job)
        }
    }
}
