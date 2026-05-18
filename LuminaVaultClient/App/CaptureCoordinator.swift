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
            self.spacesClient = SpacesHTTPClient(client: httpBase)
            let drainer = CaptureDrainer(
                queue: queue,
                vaultUploader: uploader,
                memoryClient: memory,
            )
            self.drainer = drainer
            await drainer.start()
            log.info("capture coordinator started")
        } catch {
            log.error("capture coordinator start failed: \(error.localizedDescription)")
        }
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
