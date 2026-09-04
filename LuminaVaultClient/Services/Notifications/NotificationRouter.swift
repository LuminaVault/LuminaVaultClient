// LuminaVaultClient/LuminaVaultClient/Services/Notifications/NotificationRouter.swift
//
// HER-179 — central deep-link router for APNS taps. The root view
// observes `pendingDeepLink` and reacts (switches tab, scrolls to a
// card, injects a system message into chat).

import Foundation
import LuminaVaultShared
import SwiftUI

enum APNSDeepLink: Sendable, Equatable {
    case today(highlightOutputID: UUID?)
    case think(systemMessage: String?)
    case ingestion(batchID: UUID, itemID: UUID?)
    case workflow(runID: UUID)
    /// Hermes Companion Phase 1 — an `approval` or `runCompleted` push for
    /// a run started from this app. Opens the run's detail screen, which is
    /// where the live event trail and the approval prompt live.
    case hermesRun(runID: UUID)
    case none
}

@Observable
@MainActor
final class NotificationRouter {
    var pendingDeepLink: APNSDeepLink = .none

    func consume() -> APNSDeepLink {
        let value = pendingDeepLink
        pendingDeepLink = .none
        return value
    }

    /// Parse a `UNNotificationContent.userInfo` dict produced by the
    /// server-side `APNSNotificationService`.
    func deepLink(from userInfo: [AnyHashable: Any]) -> APNSDeepLink {
        guard let categoryRaw = userInfo["category"] as? String else {
            return .none
        }
        if categoryRaw == "ingestion" {
            guard let batchIDRaw = userInfo["batchID"] as? String,
                  let batchID = UUID(uuidString: batchIDRaw)
            else {
                return .none
            }
            let itemID = (userInfo["itemID"] as? String).flatMap(UUID.init(uuidString:))
            return .ingestion(batchID: batchID, itemID: itemID)
        }
        if categoryRaw == "workflow",
           let rawRunID = userInfo["runID"] as? String,
           let runID = UUID(uuidString: rawRunID)
        {
            return .workflow(runID: runID)
        }
        guard
            let category = APNSCategory(rawValue: categoryRaw)
        else {
            return .none
        }
        switch category {
        case .digest:
            let id = (userInfo["outputID"] as? String).flatMap(UUID.init(uuidString:))
            return .today(highlightOutputID: id)
        case .nudge:
            let message = userInfo["systemMessage"] as? String
            return .think(systemMessage: message)
        case .chat:
            let message = userInfo["systemMessage"] as? String
            return .think(systemMessage: message)
        case .approval, .runCompleted:
            // `APNSHermesRunPushNotifier.basePayload` always carries `runID`
            // (the LuminaVault row id, which is what every /v1/hermes/runs
            // path takes). Without it there is nothing to open.
            guard
                let raw = userInfo["runID"] as? String,
                let runID = UUID(uuidString: raw)
            else {
                return .none
            }
            return .hermesRun(runID: runID)
        }
    }
}
