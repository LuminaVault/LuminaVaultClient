// LuminaVaultClient/LuminaVaultClient/Services/Notifications/DeviceRegistrationCoordinator.swift
//
// HER-214 — coordinates APNS device-token registration with the server.
//
// Flow:
//   1. `NotificationsAppDelegate` (HER-179) captures the device-token hex
//      after the user grants notification permission and APNS issues a
//      token to the app.
//   2. The token is handed to this coordinator via the `TokenObserver`
//      protocol on the main actor.
//   3. The coordinator POSTs the token to `/v1/devices`. The same token
//      is also persisted under `UserDefaults` so a later sign-out can
//      DELETE it without depending on the in-memory cache.
//   4. APNS may issue a new token periodically (token rotation). The
//      coordinator compares the incoming token against the last
//      registered value and POSTs again only when it differs.
//   5. Sign-out triggers `unregisterCurrentToken()` BEFORE the keychain
//      is wiped, so the DELETE call still has a valid bearer token.
//
// The coordinator is `@MainActor` because `TokenObserver` is — APNS
// delegate callbacks land on the main actor and the registered-token
// cache is a single value used to suppress redundant POSTs.

import Foundation
import LuminaVaultShared
import os

private let log = Logger(subsystem: "com.luminavault", category: "device-registration")

@MainActor
final class DeviceRegistrationCoordinator: TokenObserver {
    private let client: any DeviceClientProtocol
    private let defaults: UserDefaults
    private let platform: DevicePlatform

    /// Persisted under this key so a fresh launch (or a sign-out from a
    /// different code path) can still look up "what did we last tell the
    /// server about". The value is the hex-encoded device token.
    private static let storageKey = "her214.lastRegisteredDeviceTokenHex"

    init(
        client: any DeviceClientProtocol,
        defaults: UserDefaults = .standard,
        platform: DevicePlatform = .ios
    ) {
        self.client = client
        self.defaults = defaults
        self.platform = platform
    }

    /// HER-214 — last token successfully POSTed to `/v1/devices`. `nil`
    /// when no registration has ever succeeded (or when a sign-out wiped
    /// the persisted value).
    var lastRegisteredTokenHex: String? {
        defaults.string(forKey: Self.storageKey)
    }

    // MARK: - TokenObserver

    /// HER-179 bridge: invoked by `NotificationsAppDelegate` whenever APNS
    /// hands the app a token. Fires-and-forgets a `Task` because the
    /// `TokenObserver` protocol is sync — the delegate cannot await.
    nonisolated func tokenDidBecomeAvailable(_ tokenHex: String) {
        Task { @MainActor in
            await self.register(tokenHex: tokenHex)
        }
    }

    // MARK: - Registration

    /// POSTs the token to `/v1/devices` and, on success, persists it
    /// under `UserDefaults` so a later sign-out can DELETE it. Idempotent
    /// — if the token matches the last successful registration, the call
    /// is a no-op (the server already knows about it).
    func register(tokenHex: String) async {
        guard !tokenHex.isEmpty else { return }
        if tokenHex == lastRegisteredTokenHex { return }
        do {
            _ = try await client.register(
                DeviceRegistrationRequest(token: tokenHex, platform: platform)
            )
            defaults.set(tokenHex, forKey: Self.storageKey)
            log.info("device.register.ok len=\(tokenHex.count, privacy: .public)")
        } catch {
            // Don't persist — next launch (or rotation) will retry. The
            // server is the source of truth, so a transient failure here
            // is recoverable without operator intervention.
            log.error("device.register.failed \(String(describing: error))")
        }
    }

    /// DELETEs the persisted token from the server. Must be called BEFORE
    /// the keychain is wiped so the DELETE request can still authenticate.
    /// Clears local persistence regardless of HTTP outcome so a stale
    /// token can't be replayed on next sign-in.
    func unregisterCurrentToken() async {
        guard let tokenHex = lastRegisteredTokenHex else { return }
        defer { defaults.removeObject(forKey: Self.storageKey) }
        do {
            try await client.unregister(token: tokenHex)
            log.info("device.unregister.ok")
        } catch {
            // Logged but swallowed — sign-out must still proceed. The
            // server prunes dead tokens on push-delivery failure (see
            // APNSNotificationService BadDeviceToken handling), so a
            // leaked row is self-healing.
            log.error("device.unregister.failed \(String(describing: error))")
        }
    }
}
