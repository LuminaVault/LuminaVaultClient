import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class MultimodalCaptureViewModelTests: XCTestCase {
    func testSaveUploadsDuplicateFileNamesToDistinctItems() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultimodalCaptureViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstDirectory = root.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)

        let firstFile = firstDirectory.appendingPathComponent("report.pdf")
        let secondFile = secondDirectory.appendingPathComponent("report.pdf")
        let contents = Data("same-sized PDF placeholder".utf8)
        try contents.write(to: firstFile)
        try contents.write(to: secondFile)

        let suiteName = "MultimodalCaptureViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client = SpyIngestionClient()
        let viewModel = MultimodalCaptureViewModel(client: client, defaults: defaults)
        viewModel.add([firstFile, secondFile])

        await viewModel.save()

        let uploadedItemIDs = await client.uploadedItemIDs()
        let createdFileItemIDs = await client.createdFileItemIDs()
        XCTAssertEqual(uploadedItemIDs, createdFileItemIDs)
        XCTAssertEqual(Set(uploadedItemIDs).count, 2)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.selectedFiles.isEmpty)
    }
}

private actor SpyIngestionClient: IngestionClientProtocol {
    private let batchID = UUID()
    private var batch: IngestionBatchDTO?
    private var createdIDs: [UUID] = []
    private var uploadIDs: [UUID] = []

    func uploadedItemIDs() -> [UUID] {
        uploadIDs
    }

    func createdFileItemIDs() -> [UUID] {
        createdIDs
    }

    func create(_ request: IngestionCreateRequest) async throws -> IngestionBatchDTO {
        let items = request.items.map { item -> IngestionItemDTO in
            let id = UUID()
            if item.kind == .file {
                createdIDs.append(id)
            }
            return IngestionItemDTO(
                id: id,
                batchID: batchID,
                kind: item.kind,
                state: .awaitingUpload,
                fileName: item.fileName,
                contentType: item.contentType,
                sizeBytes: item.sizeBytes,
                uploadedBytes: 0,
                url: item.url
            )
        }
        let batch = IngestionBatchDTO(
            id: batchID,
            state: "active",
            total: items.count,
            completed: 0,
            failed: 0,
            chunkSizeBytes: 8_000_000,
            items: items
        )
        self.batch = batch
        return batch
    }

    func upload(fileURL _: URL, itemID: UUID, batch: IngestionBatchDTO) async throws -> IngestionBatchDTO {
        uploadIDs.append(itemID)
        return batch
    }

    func list() async throws -> IngestionBatchListDTO {
        IngestionBatchListDTO(batches: batch.map { [$0] } ?? [])
    }

    func detail(batchID _: UUID) async throws -> IngestionBatchDTO {
        guard let batch else { throw CocoaError(.fileNoSuchFile) }
        return batch
    }

    func retry(batchID _: UUID, itemID _: UUID) async throws -> IngestionBatchDTO {
        guard let batch else { throw CocoaError(.fileNoSuchFile) }
        return batch
    }

    func cancel(batchID _: UUID, itemID _: UUID) async throws -> IngestionBatchDTO {
        guard let batch else { throw CocoaError(.fileNoSuchFile) }
        return batch
    }

    nonisolated func events(batchID _: UUID) -> AsyncThrowingStream<IngestionEventDTO, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
