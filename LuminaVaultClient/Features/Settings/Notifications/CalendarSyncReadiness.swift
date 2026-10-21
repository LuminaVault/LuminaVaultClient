// LuminaVaultClient/LuminaVaultClient/Features/Settings/Notifications/CalendarSyncReadiness.swift
//
// Whether the calendar reaches the server, which the pre-meeting brief needs:
// the server only knows the meetings `CalendarSyncService` pushed. Two things
// have to be on, the same two `CalendarSyncCoordinator` checks — the
// LuminaVault `calendar` consent (Settings › Data Access) and the system's
// calendar permission for the app.

import EventKit
import Foundation
import LuminaVaultShared

nonisolated enum CalendarSyncReadiness: Equatable, Sendable {
    /// Both on: meetings sync, so briefs can go out.
    case ready
    /// The Data Access `calendar` consent is off, so nothing syncs.
    case consentOff
    /// iOS calendar access is denied, restricted or write-only.
    case systemAccessOff
    /// Not known (not checked yet, or the consent could not be read). The
    /// pane says nothing rather than guess.
    case unknown
}

protocol CalendarSyncReadinessChecking: Sendable {
    func readiness() async -> CalendarSyncReadiness
}

/// The app's own answer: the consent from `/v1/apple/consent`, the
/// permission from EventKit.
struct LiveCalendarSyncReadiness: CalendarSyncReadinessChecking {
    let consentClient: any AppleConsentClientProtocol

    func readiness() async -> CalendarSyncReadiness {
        guard let snapshot = try? await consentClient.get() else { return .unknown }
        // The consent comes first: turning it on is what makes the sync ask
        // for the system permission in the first place.
        guard snapshot.consents.first(where: { $0.domain == .calendar })?.allowed == true else {
            return .consentOff
        }
        return Self.readiness(for: EKEventStore.authorizationStatus(for: .event))
    }

    /// Not asked yet counts as ready: the sync asks as soon as it starts.
    nonisolated static func readiness(for status: EKAuthorizationStatus) -> CalendarSyncReadiness {
        switch status {
        case .fullAccess, .notDetermined: .ready
        case .denied, .restricted, .writeOnly: .systemAccessOff
        @unknown default: .unknown
        }
    }
}
