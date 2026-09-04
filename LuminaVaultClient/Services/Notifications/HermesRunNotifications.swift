// LuminaVaultClient/LuminaVaultClient/Services/Notifications/HermesRunNotifications.swift
//
// Hermes Companion Phase 1 — answer a tool-call approval from the lock
// screen, without launching the app.
//
// This is the whole pitch of Phase 1, so it is worth being precise about what
// iOS does and does not allow here.
//
// **Categories are registered ahead of time, not derived at delivery.**
// `UNNotificationCategory` and its actions are declared once, at launch;
// a push then selects one by `aps.category`. There is no API that reads an
// action list out of the payload at delivery time. The only way to vary
// buttons per push is a `UNNotificationServiceExtension` rewriting
// `categoryIdentifier` — a separate app target, which this change is not
// allowed to add (it would mean touching signing configuration).
//
// So the payload's `choices` list is honoured the other way round: the
// category declares every answer Hermes can ever ask for, and
// `HermesApprovalPush` refuses to send one the payload did not offer,
// falling back to opening the run instead. Nothing about which answers are
// *valid* is hardcoded — only which are *renderable*.
//
// The action identifiers are the wire values (`once`, `session`, `always`,
// `deny`), so what the user tapped is posted verbatim, and the titles come
// from the same place the in-app card gets them, so a button reads the same
// on the lock screen and in the app.

import Foundation
import LuminaVaultShared
import os
import UIKit
import UserNotifications

private let log = Logger(subsystem: "com.luminavault", category: "hermes-run-push")

enum HermesRunNotifications {
    /// Matches `APNSPushCategory.approval` on the server.
    static let approvalCategoryID = APNSCategory.approval.rawValue
    /// Matches `APNSPushCategory.runCompleted`. Plain — tapping it opens the
    /// run; there is nothing to answer.
    static let runCompletedCategoryID = APNSCategory.runCompleted.rawValue

    /// Every category the app declares. Registered from
    /// `didFinishLaunchingWithOptions` so an app cold-launched purely to
    /// service a notification action still knows about them.
    static var all: Set<UNNotificationCategory> {
        [approvalCategory, runCompletedCategory]
    }

    private static var approvalCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: approvalCategoryID,
            actions: HermesApprovalChoice.allCases.map(action(for:)),
            intentIdentifiers: [],
            options: []
        )
    }

    private static var runCompletedCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: runCompletedCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
    }

    private static func action(for choice: HermesApprovalChoice) -> UNNotificationAction {
        UNNotificationAction(
            identifier: choice.rawValue,
            title: HermesRunApprovalCard.label(for: choice),
            // No `.foreground`: the whole point is answering without opening
            // the app. `.destructive` colours Deny red on the lock screen.
            // `.authenticationRequired` on the permissive answers means a
            // locked phone must be unlocked before a tool call is allowed —
            // denying stays available without unlocking.
            options: choice == .deny ? [.destructive] : [.authenticationRequired]
        )
    }
}

/// The `approval` push payload. Built by `APNSHermesRunPushNotifier`
/// server-side: `runID`, `hermesRunID`, `status`, and a comma-separated
/// `choices`.
struct HermesApprovalPush: Equatable, Sendable {
    let runID: UUID
    let hermesRunID: String?
    /// Exactly the answers this run will accept. Hermes withholds `always`
    /// for some commands, so this is not `allCases`.
    let choices: [HermesApprovalChoice]

    init?(userInfo: [AnyHashable: Any]) {
        guard
            (userInfo["category"] as? String) == HermesRunNotifications.approvalCategoryID,
            let raw = userInfo["runID"] as? String,
            let runID = UUID(uuidString: raw)
        else {
            return nil
        }
        self.runID = runID
        hermesRunID = userInfo["hermesRunID"] as? String
        choices = Self.parseChoices(userInfo["choices"])
    }

    /// The wire form is one comma-separated string, not a JSON array — the
    /// APNS custom payload is `[String: String]` server-side.
    static func parseChoices(_ value: Any?) -> [HermesApprovalChoice] {
        guard let raw = value as? String else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap(HermesApprovalChoice.init(rawValue:))
    }

    /// `nil` when the tapped action is not an approval answer (a plain tap,
    /// or the system's default/dismiss actions).
    func choice(forActionIdentifier identifier: String) -> HermesApprovalChoice? {
        guard let choice = HermesApprovalChoice(rawValue: identifier) else { return nil }
        // Refuse an answer this run never offered rather than posting one the
        // server will reject.
        return choices.contains(choice) ? choice : nil
    }
}

/// Posts the approval from wherever the notification action was handled —
/// including a process the system woke solely to run it.
///
/// It builds its own `BaseHTTPClient` off `KeychainService.shared` rather
/// than reaching for `AppState`: on a background action launch there is no
/// SwiftUI scene, and constructing the whole app state to send one POST
/// would be both slow and fragile. Refresh is wired, because an access token
/// that expired while the phone sat in a pocket is the normal case here, not
/// an edge one.
actor HermesApprovalResponder {
    static let shared = HermesApprovalResponder()

    private let makeClient: @Sendable () -> any HermesRunsClientProtocol

    init(makeClient: (@Sendable () -> any HermesRunsClientProtocol)? = nil) {
        self.makeClient = makeClient ?? { HermesRunsHTTPClient(client: Self.backgroundHTTPClient()) }
    }

    /// Answers and reports whether the server accepted it. Never throws — a
    /// notification action has nowhere to surface one.
    @discardableResult
    func answer(runID: UUID, choice: HermesApprovalChoice) async -> Bool {
        do {
            _ = try await makeClient().approve(runID, choice: choice)
            log.info("hermes approval answered \(choice.rawValue, privacy: .public)")
            return true
        } catch {
            let failure = HermesRunsFailure(error)
            log.error("hermes approval failed \(String(describing: failure), privacy: .public)")
            return false
        }
    }

    private static func backgroundHTTPClient() -> BaseHTTPClient {
        let keychain = KeychainService.shared
        let sharedSession = SharedSessionKeychain(accessGroup: Config.keychainAccessGroup)
        let bootstrap = BaseHTTPClient(tokenProvider: { nil })
        let auth = AuthHTTPClient(client: bootstrap)
        return BaseHTTPClient(
            tokenProvider: { keychain.accessToken },
            refreshHandler: {
                guard let token = keychain.refreshToken else { throw APIError.unauthorized }
                let response = try await auth.refreshToken(token)
                keychain.accessToken = response.accessToken
                keychain.refreshToken = response.refreshToken
                sharedSession.accessToken = response.accessToken
                return response.accessToken
            }
        )
    }
}
