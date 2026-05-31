// LuminaVaultClient/LuminaVaultClient/Services/Capture/CaptureDrainer.swift
//
// HER-34 — actor that drains `CaptureQueue` against the server. Triggers:
//   * scene `willEnterForeground` (wired by `LuminaVaultClientApp`)
//   * `NWPathMonitor` reachability transition (offline → online)
//   * explicit `tick()` from a UI "retry now" gesture
//
// Each pending row goes: upload asset → memory upsert → delete on
// success. On failure the attempts counter ticks; after `maxAttempts`
// the row flips to `.failed` and surfaces in a review badge.

import Foundation
import LuminaVaultShared
import Network
import OSLog

// `Logger` is Sendable; the `nonisolated(unsafe)` opt-out keeps the file-
// scope binding usable from this actor under the project's default
// MainActor isolation.
private nonisolated(unsafe) let log = Logger(subsystem: "com.luminavault", category: "capture-drainer")

actor CaptureDrainer {
    static let maxAttempts = 6

    private let queue: CaptureQueueProtocol
    private let vaultUploader: VaultUploadClientProtocol
    private let memoryClient: MemoryClientProtocol
    /// HER-257 — optional so existing test fixtures + coordinator wiring
    /// keep compiling. Production injection comes from
    /// `CaptureCoordinator.start` once the safari client is built.
    private let safariClient: (any CaptureSafariClientProtocol)?
    private let pathPrefix: String

    private var draining = false
    private var pathMonitor: NWPathMonitor?
    private var monitorTask: Task<Void, Never>?

    init(
        queue: CaptureQueueProtocol,
        vaultUploader: VaultUploadClientProtocol,
        memoryClient: MemoryClientProtocol,
        safariClient: (any CaptureSafariClientProtocol)? = nil,
        pathPrefix: String = "raw/captures"
    ) {
        self.queue = queue
        self.vaultUploader = vaultUploader
        self.memoryClient = memoryClient
        self.safariClient = safariClient
        self.pathPrefix = pathPrefix
    }

    /// Begin watching `NWPathMonitor` and trigger a drain on each
    /// offline → online transition. Idempotent.
    func start() async {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        self.pathMonitor = monitor

        let stream = AsyncStream<NWPath.Status> { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status)
            }
            continuation.onTermination = { _ in monitor.cancel() }
        }
        monitor.start(queue: .global(qos: .utility))

        monitorTask = Task { [weak self] in
            var lastStatus: NWPath.Status = .requiresConnection
            for await status in stream {
                if status == .satisfied, lastStatus != .satisfied {
                    await self?.tick()
                }
                lastStatus = status
            }
        }

        // First tick covers anything queued before the app launched.
        await tick()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    /// Process the pending queue exactly once. Re-entrant calls are
    /// coalesced via the `draining` flag — a second call mid-tick is a
    /// no-op, the in-flight tick will see the new row when it loops.
    func tick() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }

        let rows: [CaptureRowSnapshot]
        do { rows = try await queue.pending() }
        catch {
            log.error("queue.pending failed: \(error.localizedDescription)")
            return
        }

        for row in rows {
            await drainOne(row)
        }
    }

    private func drainOne(_ row: CaptureRowSnapshot) async {
        do {
            switch row.kind {
            case .photo:
                let relativePath = "\(pathPrefix)/\(row.id.uuidString).\(row.fileExtension)"
                _ = try await vaultUploader.uploadAsset(
                    data: row.imageData,
                    contentType: row.contentType,
                    relativePath: relativePath,
                    spaceID: row.spaceID,
                )
                let memoryContent = row.captionText?.nilIfEmpty ?? "Photo capture"
                _ = try await memoryClient.upsert(MemoryUpsertRequest(
                    content: memoryContent,
                    lat: row.lat,
                    lng: row.lng,
                    accuracyM: row.accuracyM,
                    placeName: row.placeName,
                ), spaceID: row.spaceID)

            case .text:
                // HER-256 — written note. Empty bodies were already filtered by
                // the VM before enqueue, but guard here defends against schema
                // drift / hand-crafted rows so we don't POST garbage upsert.
                guard let body = row.captionText?.nilIfEmpty else {
                    try await queue.delete(id: row.id)
                    log.info("dropped empty .text capture id=\(row.id.uuidString)")
                    return
                }
                // HER-Notes — persist the note as a markdown vault file AND
                // let the server own its recall memory in one call. `uploadNote`
                // (`?note=true`) creates-or-updates the linked memory and
                // re-embeds server-side, so the note is browsable in its Space
                // and instantly current in chat. Replaces the old two-call
                // (uploadAsset + /v1/memory/upsert) flow, which left the memory
                // without lineage and unable to re-embed on edit.
                // NOTE: geo (lat/lng/placeName) is not yet carried on note
                // memories — follow-up if location-tagged notes are needed.
                guard let data = body.data(using: .utf8) else {
                    try await queue.delete(id: row.id)
                    return
                }
                let relativePath = "\(pathPrefix)/\(row.id.uuidString).md"
                _ = try await vaultUploader.uploadNote(
                    data: data,
                    contentType: "text/markdown",
                    relativePath: relativePath,
                    spaceID: row.spaceID,
                    metadata: nil,
                )

            case .textFile:
                guard let body = row.captionText?.nilIfEmpty else {
                    try await queue.delete(id: row.id)
                    log.info("dropped empty .textFile capture id=\(row.id.uuidString)")
                    return
                }
                let relativePath = "\(pathPrefix)/\(row.id.uuidString).\(row.fileExtension)"
                _ = try await vaultUploader.uploadAsset(
                    data: row.imageData,
                    contentType: row.contentType,
                    relativePath: relativePath,
                    spaceID: row.spaceID,
                )
                _ = try await memoryClient.upsert(MemoryUpsertRequest(
                    content: body,
                    lat: row.lat,
                    lng: row.lng,
                    accuracyM: row.accuracyM,
                    placeName: row.placeName,
                ), spaceID: row.spaceID)

            case .url:
                // HER-257 — URL capture: hand off to /v1/capture/safari.
                // Server enriches asynchronously (OG / oEmbed / X scrape)
                // and persists a vault file; client doesn't wait for the
                // enrichment status here, just for the synchronous insert.
                guard let safariClient else {
                    log.error("'.url' row id=\(row.id.uuidString) dropped — safari client not configured")
                    try await queue.delete(id: row.id)
                    return
                }
                guard let urlString = row.urlString?.nilIfEmpty else {
                    try await queue.delete(id: row.id)
                    log.info("dropped empty .url capture id=\(row.id.uuidString)")
                    return
                }
                _ = try await safariClient.capture(CaptureSafariRequest(
                    url: urlString,
                    notes: row.captionText?.nilIfEmpty,
                    spaceId: row.spaceID,
                ))
            }

            try await queue.delete(id: row.id)
            log.info("drained capture id=\(row.id.uuidString) kind=\(row.kind.rawValue)")
        } catch {
            let nextAttempts = row.attempts + 1
            let flipToFailed = nextAttempts >= Self.maxAttempts
            do {
                try await queue.markFailure(
                    id: row.id,
                    error: error.localizedDescription,
                    flipToFailed: flipToFailed,
                )
            } catch {
                log.error("markFailure crashed: \(error.localizedDescription)")
            }
            if flipToFailed {
                log.warning("capture id=\(row.id.uuidString) flipped to failed after \(nextAttempts) attempts")
            }
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
