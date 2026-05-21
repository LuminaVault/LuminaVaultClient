// LuminaVaultClient/LuminaVaultClient/Services/Notifications/NotificationsAppDelegate.swift
//
// HER-179 — UIApplicationDelegate + UNUserNotificationCenterDelegate for
// APNS. Captures the device token on registration and surfaces taps
// to the shared NotificationRouter.

import Foundation
import UIKit
import UserNotifications
import os

private let log = Logger(subsystem: "com.luminavault", category: "apns")

final class NotificationsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = NotificationsAppDelegate()

    /// Last captured device token, hex-encoded. Sent to the server by
    /// the device-registration flow once the user is authenticated.
    @MainActor private(set) var deviceTokenHex: String?

    /// MainActor-isolated bridge; set by `LuminaVaultClientApp` on launch.
    @MainActor weak var router: NotificationRouter?

    @MainActor weak var onTokenAvailable: TokenObserver?

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
        Task { @MainActor in
            if let link = self.router?.deepLink(from: userInfo), link != .none {
                self.router?.pendingDeepLink = link
            }
        }
        completionHandler()
    }
}

@MainActor
protocol TokenObserver: AnyObject {
    func tokenDidBecomeAvailable(_ tokenHex: String)
}
