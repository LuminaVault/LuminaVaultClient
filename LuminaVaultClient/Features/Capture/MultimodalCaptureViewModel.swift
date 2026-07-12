import Foundation
import LuminaVaultShared
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class MultimodalCaptureViewModel {
    private let client: any IngestionClientProtocol
    private let defaults: UserDefaults
    private let capabilitiesClient: (any HermesCapabilitiesClientProtocol)?
    private let spacesClient: (any SpacesClientProtocol)?
    private static let latestBatchKey = "lv.ingestion.latestBatch"
    private static let selectedSpaceKey = "lv.ingestion.selectedSpace"
    var selectedFiles: [URL] = []
    var urlText = ""
    var saving = false
    var errorMessage: String?
    var latestBatch: IngestionBatchDTO? {
        didSet { persistLatestBatch() }
    }

    var hermesCapabilities: HermesCapabilities?
    var spaces: [SpaceDTO] = []
    var selectedSpaceID: UUID? {
        didSet { defaults.set(selectedSpaceID?.uuidString, forKey: Self.selectedSpaceKey) }
    }

    init(
        client: any IngestionClientProtocol,
        capabilitiesClient: (any HermesCapabilitiesClientProtocol)? = nil,
        spacesClient: (any SpacesClientProtocol)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.capabilitiesClient = capabilitiesClient
        self.spacesClient = spacesClient
        self.defaults = defaults
        selectedSpaceID = defaults.string(forKey: Self.selectedSpaceKey).flatMap(UUID.init(uuidString:))
        latestBatch = defaults.data(forKey: Self.latestBatchKey)
            .flatMap { try? JSONDecoder().decode(IngestionBatchDTO.self, from: $0) }
    }

    var canSave: Bool {
        !saving && !captureBlocked && (!selectedFiles.isEmpty || !urls.isEmpty)
    }

    var captureBlocked: Bool {
        hermesCapabilities?.isUserOverride == true && hermesCapabilities?.multimodalIngestion == .unsupported
    }

    var urls: [String] {
        urlText.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
    }

    func add(_ urls: [URL]) {
        for url in urls where !selectedFiles.contains(url) {
            guard supports(url) else {
                errorMessage = "\(url.lastPathComponent) is not supported by the connected Hermes."
                continue
            }
            selectedFiles.append(url)
        }
    }

    func remove(_ url: URL) {
        selectedFiles.removeAll { $0 == url }
    }

    func save() async {
        await loadCapabilities()
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
            var batch = try await client.create(IngestionCreateRequest(spaceID: selectedSpaceID, items: fileInputs + urlInputs))
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

    func loadCapabilities() async {
        guard let capabilitiesClient else { return }
        do { hermesCapabilities = try await capabilitiesClient.get().capabilities }
        catch { /* Server-side validation remains authoritative. */ }
    }

    func loadSpaces() async {
        guard let spacesClient else { return }
        do {
            spaces = try await spacesClient.list()
            if let selectedSpaceID, !spaces.contains(where: { $0.id == selectedSpaceID }) {
                self.selectedSpaceID = nil
            }
        } catch { /* Inbox remains available when Spaces cannot be loaded. */ }
    }

    func refreshStatus() async {
        guard let batchID = latestBatch?.id else { return }
        do {
            latestBatch = try await client.detail(batchID: batchID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func monitorStatus() async {
        while !Task.isCancelled, latestBatch?.state == "active" {
            await refreshStatus()
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
        }
    }

    func retry(itemID: UUID) async {
        guard let batchID = latestBatch?.id else { return }
        await update { try await client.retry(batchID: batchID, itemID: itemID) }
    }

    func cancel(itemID: UUID) async {
        guard let batchID = latestBatch?.id else { return }
        await update { try await client.cancel(batchID: batchID, itemID: itemID) }
    }

    private func update(_ operation: () async throws -> IngestionBatchDTO) async {
        do { latestBatch = try await operation() }
        catch { errorMessage = error.localizedDescription }
    }

    private func persistLatestBatch() {
        guard let latestBatch, let data = try? JSONEncoder().encode(latestBatch) else {
            defaults.removeObject(forKey: Self.latestBatchKey)
            return
        }
        defaults.set(data, forKey: Self.latestBatchKey)
    }

    private func supports(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        if let maximum = hermesCapabilities?.ingestionMaxSourceBytes,
           let size = values?.fileSize, Int64(size) > maximum
        {
            return false
        }
        guard let patterns = hermesCapabilities?.ingestionSupportedMimeTypes,
              let type = values?.contentType?.preferredMIMEType else { return true }
        return patterns.contains { pattern in
            let normalized = pattern.lowercased()
            return normalized.hasSuffix("/*")
                ? type.lowercased().hasPrefix(String(normalized.dropLast()))
                : type.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }
}
