import Foundation
import LuminaVaultShared

protocol IngestionClientProtocol: Sendable {
    func create(_ request: IngestionCreateRequest) async throws -> IngestionBatchDTO
    func upload(fileURL: URL, itemID: UUID, batch: IngestionBatchDTO) async throws -> IngestionBatchDTO
    func list() async throws -> IngestionBatchListDTO
    func detail(batchID: UUID) async throws -> IngestionBatchDTO
    func retry(batchID: UUID, itemID: UUID) async throws -> IngestionBatchDTO
    func cancel(batchID: UUID, itemID: UUID) async throws -> IngestionBatchDTO
}

final class IngestionHTTPClient: IngestionClientProtocol, Sendable {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func create(_ request: IngestionCreateRequest) async throws -> IngestionBatchDTO {
        try await client.execute(IngestionEndpoints.Create(request: request))
    }

    func upload(fileURL: URL, itemID: UUID, batch: IngestionBatchDTO) async throws -> IngestionBatchDTO {
        let handle = try FileHandle(forReadingFrom: fileURL)
        do {
            let uploadedBytes = batch.items.first(where: { $0.id == itemID })?.uploadedBytes ?? 0
            let alignedBytes = uploadedBytes - (uploadedBytes % Int64(batch.chunkSizeBytes))
            try handle.seek(toOffset: UInt64(alignedBytes))
            var index = Int(alignedBytes / Int64(batch.chunkSizeBytes))
            while let data = try handle.read(upToCount: batch.chunkSizeBytes), !data.isEmpty {
                _ = try await client.uploadBytes(
                    path: "/v1/ingestions/\(batch.id.uuidString)/items/\(itemID.uuidString)/chunks/\(index)",
                    method: .put,
                    body: data,
                    contentType: "application/octet-stream"
                )
                index += 1
            }
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        return try await client.execute(IngestionEndpoints.Complete(batchID: batch.id, itemID: itemID))
    }

    func list() async throws -> IngestionBatchListDTO {
        try await client.execute(IngestionEndpoints.List())
    }

    func detail(batchID: UUID) async throws -> IngestionBatchDTO {
        try await client.execute(IngestionEndpoints.Detail(batchID: batchID))
    }

    func retry(batchID: UUID, itemID: UUID) async throws -> IngestionBatchDTO {
        try await client.execute(IngestionEndpoints.Retry(batchID: batchID, itemID: itemID))
    }

    func cancel(batchID: UUID, itemID: UUID) async throws -> IngestionBatchDTO {
        try await client.execute(IngestionEndpoints.Cancel(batchID: batchID, itemID: itemID))
    }
}

enum IngestionEndpoints {
    struct Create: Endpoint {
        typealias Response = IngestionBatchDTO
        let request: IngestionCreateRequest
        var path: String {
            "/v1/ingestions"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }

    struct List: Endpoint {
        typealias Response = IngestionBatchListDTO
        var path: String {
            "/v1/ingestions"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct Complete: Endpoint {
        typealias Response = IngestionBatchDTO
        let batchID: UUID
        let itemID: UUID
        var path: String {
            "/v1/ingestions/\(batchID.uuidString)/items/\(itemID.uuidString)/complete"
        }

        var method: HTTPMethod {
            .post
        }
    }

    struct Detail: Endpoint {
        typealias Response = IngestionBatchDTO
        let batchID: UUID
        var path: String {
            "/v1/ingestions/\(batchID.uuidString)"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct Retry: Endpoint {
        typealias Response = IngestionBatchDTO
        let batchID: UUID
        let itemID: UUID
        var path: String {
            "/v1/ingestions/\(batchID.uuidString)/items/\(itemID.uuidString)/retry"
        }

        var method: HTTPMethod {
            .post
        }
    }

    struct Cancel: Endpoint {
        typealias Response = IngestionBatchDTO
        let batchID: UUID
        let itemID: UUID
        var path: String {
            "/v1/ingestions/\(batchID.uuidString)/items/\(itemID.uuidString)"
        }

        var method: HTTPMethod {
            .delete
        }
    }
}
