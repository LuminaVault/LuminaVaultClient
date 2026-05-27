// LuminaVaultClient/LuminaVaultClient/Services/AppGroup/SharedSessionKeychain.swift
//
// Stores only the bearer access token in a keychain access group shared by
// the host app and share extension. Refresh tokens stay in the host app's
// private keychain.

import Foundation

struct SharedSessionKeychain: Sendable {
    private static let service = "com.luminavault.shared-session"

    private let keychain: KeychainService?

    init(accessGroup: String?) {
        guard let accessGroup, !accessGroup.isEmpty else {
            self.keychain = nil
            return
        }
        self.keychain = KeychainService(service: Self.service, accessGroup: accessGroup)
    }

    var accessToken: String? {
        get { keychain?.accessToken }
        nonmutating set { keychain?.accessToken = newValue }
    }

    func clear() {
        keychain?.accessToken = nil
    }
}
