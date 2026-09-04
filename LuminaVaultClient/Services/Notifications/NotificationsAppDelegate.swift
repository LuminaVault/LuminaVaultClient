// LuminaVaultClient/LuminaVaultClient/Services/Notifications/NotificationsAppDelegate.swift
//
// HER-179 — UIApplicationDelegate + UNUserNotificationCenterDelegate for
// APNS. Captures the device token on registration and surfaces taps
// to the shared NotificationRouter.

import Foundation
import os
import UIKit
import UserNotifications

private let log = Logger(subsystem: "com.luminavault", category: "apns")

final class NotificationsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = NotificationsAppDelegate()

    /// Last captured device token, hex-encoded. Sent to the server by
    /// the device-registration flow once the user is authenticated.
    @MainActor private(set) var deviceTokenHex: String?

    /// MainActor-isolated bridge; set by `LuminaVaultClientApp` on launch.
    @MainActor weak var router: NotificationRouter?

    @MainActor weak var onTokenAvailable: TokenObserver?

    /// HER-214 — true when the system has not yet asked the user about
    /// notifications. Callers gate the `requestAuthorizationAndRegister()`
    /// prompt on this so an already-denied or already-granted user
    /// doesn't see a redundant authorization request mid-session.
    static func shouldRequestAuthorization() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .notDetermined
    }

    /// Asks the user to allow notifications and registers for remote
    /// notifications if granted. Idempotent.
    @MainActor func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            await UIApplication.shared.registerForRemoteNotifications()
        } catch {
            log.error("apns.authorization.failed \(String(describing: error))")
        }
    }

    // MARK: - UIApplicationDelegate

    /// The delegate and the notification categories are installed here, not
    /// from the SwiftUI scene, for two reasons that both matter to Phase 1:
    ///
    /// 1. iOS delivers a notification response only to a delegate that is
    ///    already set when the app finishes launching. Previously the
    ///    delegate was assigned inside `requestAuthorizationAndRegister()`,
    ///    which runs only when authorization is still `.notDetermined` — so
    ///    on any launch by an already-authorized user, taps were dropped.
    /// 2. Answering an approval from the lock screen can cold-launch the app
    ///    into the background with no scene at all. Categories must already
    ///    be registered by then or the action buttons never render.
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(HermesRunNotifications.all)
        return true
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            self.deviceTokenHex = hex
            self.onTokenAvailable?.tokenDidBecomeAvailable(hex)
            log.info("apns.token.received len=\(deviceToken.count, privacy: .public)")
        }
    }

    func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundIngestionUploader.sessionIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor in BackgroundIngestionUploader.shared.handleEventsCompletion(completionHandler) }
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        log.error("apns.register.failed \(String(describing: error))")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Foreground delivery — still show banner, but also record the deep-link.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        Task { @MainActor in
            if let link = self.router?.deepLink(from: userInfo), link != .none {
                self.router?.pendingDeepLink = link
            }
        }
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Phase 1 — an approval answered straight from the notification. The
        // actions are not `.foreground`, so the app may have been woken
        // purely to run this and has only a short window before it is
        // suspended again: hold a background-task assertion until the POST
        // lands, and only then call the completion handler.
        if let push = HermesApprovalPush(userInfo: userInfo),
           let choice = push.choice(forActionIdentifier: response.actionIdentifier)
        {
            Self.answerApproval(push: push, choice: choice, completionHandler: completionHandler)
            return
        }

        Task { @MainActor in
            if let link = self.router?.deepLink(from: userInfo), link != .none {
                self.router?.pendingDeepLink = link
            }
        }
        completionHandler()
    }

    /// Sends the approval, keeping the process alive for the round trip. On
    /// failure the run is queued as a deep link so the next foreground shows
    /// the user the prompt they thought they had answered, rather than
    /// silently dropping it.
    private static func answerApproval(
        push: HermesApprovalPush,
        choice: HermesApprovalChoice,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            let application = UIApplication.shared
            var assertion = UIBackgroundTaskIdentifier.invalid
            assertion = application.beginBackgroundTask(withName: "hermes.approval") {
                application.endBackgroundTask(assertion)
                assertion = .invalid
            }
            let accepted = await HermesApprovalResponder.shared.answer(runID: push.runID, choice: choice)
            if !accepted {
                shared.router?.pendingDeepLink = .hermesRun(runID: push.runID)
            }
            if assertion != .invalid {
                application.endBackgroundTask(assertion)
            }
            completionHandler()
        }
    }
}

@MainActor
protocol TokenObserver: AnyObject {
    func tokenDidBecomeAvailable(_ tokenHex: String)
}
