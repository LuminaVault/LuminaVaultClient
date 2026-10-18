// LuminaVaultClient/LuminaVaultClient/Services/Notifications/ResurfaceNotifications.swift
//
// Pushes that bring a memory back, and the three plain ones that ride along
// with them.
//
// `resurface` carries four answers — Keep, Soon, Later, Never — that post a
// memory review straight from the notification, without opening the app,
// the same way an approval is answered (see `HermesRunNotifications`).
// `learned`, `brief` and `meeting` each carry one foreground button that
// opens the app on the push's deep link.
//
// Payload contract for `resurface`: `memoryId` (a UUID string) and
// `deepLink` (`luminavault://memory/<id>`). A plain tap routes the deep link
// like any other push.
//
// None of these four is an `APNSCategory` in LuminaVaultShared yet, so the
// identifiers are the server's wire strings, spelled here once.

import Foundation
import LuminaVaultShared
import os
import UIKit
import UserNotifications

nonisolated private let log = Logger(subsystem: "com.luminavault", category: "resurface-push")

enum ResurfaceNotifications {
    static let resurfaceCategoryID = "resurface"
    static let learnedCategoryID = "learned"
    static let briefCategoryID = "brief"
    static let meetingCategoryID = "meeting"

    /// The one action identifier the three foreground categories share.
    static let openActionID = "open"

    static var categories: Set<UNNotificationCategory> {
        [
            resurfaceCategory,
            openCategory(learnedCategoryID, title: "Review"),
            openCategory(briefCategoryID, title: "Open"),
            openCategory(meetingCategoryID, title: "Open"),
        ]
    }

    /// Action identifiers are the review actions' wire values, so what was
    /// tapped maps straight to what is posted.
    static func actionTitle(for action: MemoryReviewAction) -> String {
        switch action {
        case .kept: "Keep"
        case .soon: "Soon"
        case .later: "Later"
        case .never: "Never"
        }
    }

    /// Keep, Soon, Later, Never — the card's order.
    static let actionOrder: [MemoryReviewAction] = [.kept, .soon, .later, .never]

    private static var resurfaceCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: resurfaceCategoryID,
            actions: actionOrder.map { action in
                UNNotificationAction(
                    identifier: action.rawValue,
                    title: actionTitle(for: action),
                    // No `.foreground`: answered without opening the app.
                    // Never is red because it is the one that sticks.
                    options: action == .never ? [.destructive] : []
                )
            },
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "A memory to revisit",
            options: []
        )
    }

    private static func openCategory(_ id: String, title: String) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: id,
            actions: [UNNotificationAction(identifier: openActionID, title: title, options: [.foreground])],
            intentIdentifiers: [],
            options: []
        )
    }
}

/// A `resurface` push, read from its `userInfo`.
struct ResurfacePush: Equatable, Sendable {
    let memoryID: UUID

    /// Nil for anything that is not a resurface push naming a memory. The
    /// category is read from the custom `category` key or, failing that,
    /// `aps.category`; the id from `memoryId` or, failing that, the deep link.
    init?(userInfo: [AnyHashable: Any]) {
        let aps = userInfo["aps"] as? [String: Any]
        let category = (userInfo["category"] as? String) ?? (aps?["category"] as? String)
        guard category == ResurfaceNotifications.resurfaceCategoryID else { return nil }
        if let raw = userInfo["memoryId"] as? String, let id = UUID(uuidString: raw) {
            memoryID = id
        } else if let raw = userInfo["deepLink"] as? String,
                  let url = URL(string: raw),
                  case let .memory(id) = NotificationRouter.deepLink(from: url)
        {
            memoryID = id
        } else {
            return nil
        }
    }

    /// The review a tapped action asks for. Nil for a plain tap or the
    /// system's dismiss action, which route (or do nothing) instead.
    static func action(forActionIdentifier identifier: String) -> MemoryReviewAction? {
        MemoryReviewAction(rawValue: identifier)
    }
}

/// Posts a review from a notification action, including from a process the
/// system woke only to run it. Same shape as `HermesApprovalResponder`, and
/// the same client: `backgroundHTTPClient()` builds one off the keychain with
/// refresh wired, because there is no `AppState` on a background launch.
actor ResurfaceReviewResponder {
    static let shared = ResurfaceReviewResponder()

    private let makeClient: @Sendable @MainActor () -> any MemoryClientProtocol

    init(makeClient: (@Sendable @MainActor () -> any MemoryClientProtocol)? = nil) {
        self.makeClient = makeClient ?? { MemoryHTTPClient(client: HermesApprovalResponder.backgroundHTTPClient()) }
    }

    /// Whether the server took it. Never throws — a notification action has
    /// nowhere to show an error.
    @discardableResult
    func review(memoryID: UUID, action: MemoryReviewAction) async -> Bool {
        do {
            _ = try await makeClient().review(id: memoryID, action: action)
            log.info("resurface review sent \(action.rawValue, privacy: .public)")
            return true
        } catch {
            log.error("resurface review failed \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
