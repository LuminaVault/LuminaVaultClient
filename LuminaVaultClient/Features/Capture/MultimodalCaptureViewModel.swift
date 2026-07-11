import Foundation
import LuminaVaultShared
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class MultimodalCaptureViewModel {
    private let client: any IngestionClientProtocol
    var selectedFiles: [URL] = []
    var urlText = ""
    var saving = false
    var errorMessage: String?
    var latestBatch: IngestionBatchDTO?

    init(client: any IngestionClientProtocol) {
        self.client = client
    }

    var canSave: Bool {
        !saving && (!selectedFiles.isEmpty || !urls.isEmpty)
    }

    var urls: [String] {
        urlText.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
    }

    func add(_ urls: [URL]) {
        for url in urls where !selectedFiles.contains(url) {
            selectedFiles.append(url)
        }
    }

    func remove(_ url: URL) {
        selectedFiles.removeAll { $0 == url }
    }

    func save() async {
        guard canSave else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        let access = selectedFiles.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer { for (url, granted) in access where granted {
            url.stopAccessingSecurityScopedResource()
        } }
        do {
            let fileInputs = try selectedFiles.map { url -> IngestionCreateItemRequest in
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                return IngestionCreateItemRequest(
                    kind: .file,
                    fileName: url.lastPathComponent,
                    contentType: values.contentType?.preferredMIMEType ?? "application/octet-stream",
                    sizeBytes: Int64(values.fileSize ?? 0)
                )
            }
            let urlInputs = urls.map { IngestionCreateItemRequest(kind: .url, url: $0) }
            var batch = try await client.create(IngestionCreateRequest(items: fileInputs + urlInputs))
            for file in selectedFiles {
                guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      let item = batch.items.first(where: { $0.fileName == file.lastPathComponent && $0.sizeBytes == Int64(size) })
                else { continue }
                batch = try await client.upload(fileURL: file, itemID: item.id, batch: batch)
            }
            latestBatch = batch
            selectedFiles = []
            urlText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshStatus() async {
        guard let batchID = latestBatch?.id else { return }
        do {
            latestBatch = try await client.list().batches.first { $0.id == batchID } ?? latestBatch
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
