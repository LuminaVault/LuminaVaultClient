// LuminaVaultClient/LuminaVaultClient/App/PhotoIndexCoordinator.swift
//
// Glue between AppState's auth lifecycle and PhotoIndexService — mirrors
// `HealthKitCoordinator`. Hold one instance for the app lifetime; call
// `start()` after login.
//
// `start()`:
//   1. Check the `.photos` consent domain server-side (AppleConsentHTTPClient).
//      If the user hasn't allowed Photos, do nothing — no auth prompt, no scan.
//   2. Otherwise run one bounded incremental scan off the main actor.
//
// Idempotent and cheap: the consent check short-circuits before any Photos
// authorization prompt, so a user who declined Photos never sees a system
// dialog from this path.

import Foundation
import LuminaVaultShared
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "photos.coordinator")

@MainActor
final class PhotoIndexCoordinator {
    private let service: PhotoIndexService
    private let consentClient: any AppleConsentClientProtocol
    private(set) var lastScanDate: Date?
    private var isRunning = false

    init(service: PhotoIndexService, consentClient: any AppleConsentClientProtocol) {
        self.service = service
        self.consentClient = consentClient
    }

    /// Consent-gated kick. Safe to call repeatedly (launch + foreground).
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        guard await isPhotosAllowed() else {
            log.info("photos index skipped — .photos consent not granted")
            return
        }
        await service.scanIfAuthorized()
        lastScanDate = Date()
    }

    private func isPhotosAllowed() async -> Bool {
        do {
            let snapshot = try await consentClient.get()
            return snapshot.consents.first { $0.domain == .photos }?.allowed ?? false
        } catch {
            // Fail closed — never scan/prompt on an indeterminate consent state.
            log.error("photos consent check failed: \(error.localizedDescription)")
            return false
        }
    }
}
