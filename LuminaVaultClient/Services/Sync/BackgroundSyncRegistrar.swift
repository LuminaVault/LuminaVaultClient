// LuminaVaultClient/LuminaVaultClient/Services/Sync/BackgroundSyncRegistrar.swift
import BackgroundTasks
import Foundation
import os

/// HER-39 — registers and schedules `BGTaskScheduler` identifiers used by the
/// offline sync engine. Two identifiers, both declared in Info.plist:
///
///   * `com.lumina.fernando.sync.refresh` — `BGAppRefreshTask`, fires roughly
///     every 15 minutes when the system decides it's a good time. Drains
///     small queues opportunistically.
///   * `com.lumina.fernando.sync.processing` — `BGProcessingTask`, requires
///     network + power. Used for catch-up drains after long offline windows.
///
/// `register()` MUST be called once during app launch — from the main thread,
/// before any scenes activate — or BGTaskScheduler will fatal at first
/// `submit`. `scheduleNext()` is safe to call at any point and is invoked on
/// every scenePhase → .background transition in `LuminaVaultClientApp`.
///
/// Phase D wires the actual drain handler. For now `register()` accepts an
/// optional `drainHandler` so a future call site can replace the no-op
/// without changing this file's surface.
enum BackgroundSyncRegistrar {
    static let refreshIdentifier = "com.lumina.fernando.sync.refresh"
    static let processingIdentifier = "com.lumina.fernando.sync.processing"

    private static let logger = Logger(subsystem: "com.lumina.fernando", category: "bgsync")

    /// Calls into the registered drain handler, if any, when a background
    /// task fires. Phase D replaces this with `SyncManager.runUntilDrained`.
    @MainActor static var drainHandler: (@MainActor @Sendable () async -> Void)?

    static func register() {
        let scheduler = BGTaskScheduler.shared

        scheduler.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
            handleTask(task, kind: "refresh")
        }
        scheduler.register(forTaskWithIdentifier: processingIdentifier, using: nil) { task in
            handleTask(task, kind: "processing")
        }
    }

    /// Schedules the next BGProcessingTask (charging + Wi-Fi, catch-up drain)
    /// AND the next BGAppRefreshTask (lighter, opportunistic). Safe to call
    /// repeatedly — BGTaskScheduler de-duplicates submissions per identifier.
    static func scheduleNext(processingDelaySeconds: TimeInterval = 60,
                              refreshDelaySeconds: TimeInterval = 15 * 60) {
        let processing = BGProcessingTaskRequest(identifier: processingIdentifier)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = true
        processing.earliestBeginDate = Date(timeIntervalSinceNow: processingDelaySeconds)

        let refresh = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: refreshDelaySeconds)

        do {
            try BGTaskScheduler.shared.submit(processing)
            try BGTaskScheduler.shared.submit(refresh)
        } catch {
            // `notPermitted` is normal in the simulator and in DEBUG builds
            // without the BGTaskScheduler entitlement on a paid profile —
            // log + carry on.
            logger.warning("HER-39: failed to schedule background sync: \(String(describing: error), privacy: .public)")
        }
    }

    private static func handleTask(_ task: BGTask, kind: String) {
        logger.debug("HER-39: background sync fired (\(kind, privacy: .public))")

        // Reschedule the next run before starting work so a crash mid-drain
        // doesn't permanently disable background sync.
        scheduleNext()

        let work = Task { @MainActor in
            await drainHandler?()
        }

        task.expirationHandler = {
            work.cancel()
        }

        Task { @MainActor in
            _ = await work.value
            task.setTaskCompleted(success: true)
        }
    }
}
