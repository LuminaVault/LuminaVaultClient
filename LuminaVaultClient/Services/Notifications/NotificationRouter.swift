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
    /// Muse Stage D — a proactive chat message (`chat` push carrying
    /// `conversationID`), a `luminavault://chat/<id>` URL, or a tap on the
    /// agent-run Live Activity. Opens that thread in the AI tab.
    case conversation(id: UUID)
    /// `luminavault://memory/<id>` — one memory, opened as a sheet over
    /// whatever is on screen.
    case memory(id: UUID)
    /// `luminavault://learned` — "What I learned this week", opened as a
    /// sheet. The `learned` push carries it as its `deepLink`, so both a
    /// plain tap and its "Review" action land here.
    case learned
    /// `luminavault://brief` — today's brief as cards, opened as a sheet.
    /// The daily brief's chat message links here, and so does its push:
    /// a plain tap and its "Open" action alike.
    case brief
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
        let aps = userInfo["aps"] as? [String: Any]
        guard let categoryRaw = (userInfo["category"] as? String) ?? (aps?["category"] as? String) else {
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
        if let push = ResurfacePush(userInfo: userInfo) {
            return .memory(id: push.memoryID)
        }
        // The daily brief's push rides the `chat` category, so the chat
        // opt-out gates it, and carries the thread its one-line message
        // landed in. Its `deepLink` is what it is for, though: the cards.
        // Checked before the category so `.chat` does not open the thread.
        if let raw = userInfo["deepLink"] as? String,
           let url = URL(string: raw),
           Self.deepLink(from: url) == .brief
        {
            return .brief
        }
        guard
            let category = APNSCategory(rawValue: categoryRaw)
        else {
            // A category this build has no case for (`learned`, `brief`,
            // `meeting`, …) still opens wherever its deep link points.
            guard let raw = userInfo["deepLink"] as? String, let url = URL(string: raw) else {
                return .none
            }
            return Self.deepLink(from: url)
        }
        switch category {
        case .digest:
            let id = (userInfo["outputID"] as? String).flatMap(UUID.init(uuidString:))
            return .today(highlightOutputID: id)
        case .nudge:
            let message = userInfo["systemMessage"] as? String
            return .think(systemMessage: message)
        case .chat:
            // Muse Stage D — a proactive message names its thread. Prefer
            // the explicit id; fall back to the deep link it also carries.
            if let raw = userInfo["conversationID"] as? String,
               let id = UUID(uuidString: raw)
            {
                return .conversation(id: id)
            }
            if let raw = userInfo["deepLink"] as? String,
               let url = URL(string: raw),
               case let .conversation(id) = Self.deepLink(from: url)
            {
                return .conversation(id: id)
            }
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

    /// Parse an app URL. These are recognised:
    ///
    /// * `luminavault://chat/<conversationID>` — the `deepLink` the server
    ///   puts on a proactive chat push and the `widgetURL` of the agent-run
    ///   Live Activity.
    /// * `luminavault://memory/<memoryID>` — one memory.
    /// * `luminavault://learned` — "What I learned this week".
    /// * `luminavault://brief` — today's brief.
    ///
    /// Everything else is `.none`, so `onOpenURL` can fall through to its
    /// other handlers.
    static func deepLink(from url: URL) -> APNSDeepLink {
        guard url.scheme?.lowercased() == "luminavault" else { return .none }
        let segments = url.pathComponents.filter { $0 != "/" }
        if url.host?.lowercased() == "learned" {
            return segments.isEmpty ? .learned : .none
        }
        if url.host?.lowercased() == "brief" {
            return segments.isEmpty ? .brief : .none
        }
        guard segments.count == 1, let id = UUID(uuidString: segments[0]) else { return .none }
        switch url.host?.lowercased() {
        case "chat": return .conversation(id: id)
        case "memory": return .memory(id: id)
        default: return .none
        }
    }

    /// Whether a notification that arrives while the app is open should
    /// move the user. A chat push must not: the banner is the news, and
    /// yanking someone out of what they are typing into another thread is
    /// the opposite of a companion. Only a tap routes it.
    static func routesOnForegroundDelivery(_ link: APNSDeepLink) -> Bool {
        if case .conversation = link { return false }
        // Same for a resurfaced memory: popping a sheet over what the user is
        // doing because a memory came due is the opposite of a gentle nudge.
        if case .memory = link { return false }
        // And for the weekly "what I learned": the banner is the invitation.
        if case .learned = link { return false }
        // The brief's push is `passive`: it arrives quietly and opens on a tap.
        if case .brief = link { return false }
        return link != .none
    }
}
