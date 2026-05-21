// LuminaVaultClient/LuminaVaultClient/App/CaptureCoordinator.swift
//
// HER-34 — owns the lifetime of the SwiftData `ModelContainer`, the
// `CaptureQueue` actor, and the `CaptureDrainer` actor. Wired by
// `LuminaVaultClientApp` after authentication + vault initialization.
// Style mirrors `HealthKitCoordinator` (HER-202) — one instance per
// app session, started after login, stopped on sign-out.

import Foundation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.luminavault", category: "capture.coordinator")

@MainActor
final class CaptureCoordinator {
    private(set) var queue: CaptureQueue?
    private(set) var drainer: CaptureDrainer?
    /// HER-CaptureTab — exposed so `CaptureFAB` can hand the Spaces
    /// client to the picker VM without giving it AppState access.
    private(set) var spacesClient: (any SpacesClientProtocol)?
    private var container: ModelContainer?

    private let tokenProvider: @Sendable () async -> String?

    init(tokenProvider: @escaping @Sendable () async -> String?) {
        self.tokenProvider = tokenProvider
    }

    func start() async {
        guard queue == nil else { return }
        do {
            let container = try CaptureQueue.makeProductionContainer()
            self.container = container
            let queue = CaptureQueue(container: container)
            self.queue = queue

            let httpBase = BaseHTTPClient(tokenProvider: tokenProvider)
            let uploader = VaultUploadHTTPClient(client: httpBase)
            let memory = MemoryHTTPClient(client: httpBase)
            let safari = CaptureSafariHTTPClient(client: httpBase)
            self.spacesClient = SpacesHTTPClient(client: httpBase)
            let drainer = CaptureDrainer(
                queue: queue,
                vaultUploader: uploader,
                memoryClient: memory,
                safariClient: safari,
            )
            self.drainer = drainer
            await drainer.start()

            // HER-258 — replay any shares queued by `LuminaVaultShareExtension`
            // while the app was backgrounded. Each row becomes a `.url`
            // capture in the live queue; the drainer picks them up on
            // the next tick (already kicked above via `drainer.start()`).
            await drainShareExtensionQueue(into: queue)

            log.info("capture coordinator started")
        } catch {
            log.error("capture coordinator start failed: \(error.localizedDescription)")
        }
    }

    /// HER-258 — drain the App Group `pendingShares.json` that the
    /// Share Extension wrote while the host app was suspended or
    /// terminated. Best-effort: per-row failures are logged but never
    /// block startup, since a broken row in the App Group must never
    /// hard-fail the capture coordinator.
    private func drainShareExtensionQueue(into queue: CaptureQueue) async {
        let pending: [PendingShare]
        do {
            pending = try SharedShareQueue.drainAndClear()
        } catch {
            log.error("AppGroup drain failed: \(error.localizedDescription)")
            return
        }
        guard !pending.isEmpty else { return }
        log.info("draining \(pending.count) share-extension capture(s)")
        for share in pending {
            do {
                try await queue.enqueue(CaptureSnapshot.url(
                    id: share.id,
                    url: share.url,
                    note: share.note,
                    spaceID: share.spaceID,
                    createdAt: share.capturedAt,
                ))
            } catch {
                log.error("enqueue failed for share id=\(share.id.uuidString): \(error.localizedDescription)")
            }
        }
        await drainer?.tick()
    }

    func stop() async {
        await drainer?.stop()
        drainer = nil
        queue = nil
        spacesClient = nil
        container = nil
        log.info("capture coordinator stopped")
    }

    /// Bridge used by `CapturePhotosViewModel` to kick a drain after a
    /// save. Held weak via the `Sendable` closure indirection so the VM
    /// doesn't extend the coordinator's lifetime.
    var drainerHandle: CaptureDrainerHandle {
        CaptureDrainerHandle(kick: { [weak drainer] in
            await drainer?.tick()
        })
    }
}
