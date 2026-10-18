// LuminaVaultClient/LuminaVaultClient/Services/AppGroup/ExtensionAPIConfig.swift
//
// Where an app extension finds the API and the signed-in session.
//
// Compiled into the share extension and the widget extension. Both read
// `API_BASE_URL` and `KEYCHAIN_ACCESS_GROUP` from their own Info.plist —
// filled from the same `Config.<variant>.xcconfig` as the app — and the
// bearer token the app mirrors into the shared keychain group
// (`SharedSessionKeychain`). Only the access token is shared; the refresh
// token stays in the app, so an extension whose token has expired fails its
// call and leaves the work for the app.
//
// Foundation only: neither extension links LuminaVaultShared.

import Foundation

nonisolated enum ExtensionAPIConfig {
    static var apiBaseURL: URL {
        if let raw = infoString("API_BASE_URL"), let url = URL(string: raw) { return url }
        return fallbackBaseURL
    }

    // A literal that always parses; the unwrap cannot fail.
    // swiftlint:disable:next force_unwrapping
    private static let fallbackBaseURL = URL(string: "https://api.luminavault.com")!

    static var keychainAccessGroup: String? {
        infoString("KEYCHAIN_ACCESS_GROUP")
    }

    /// The access token the app last mirrored for its extensions, if any.
    static var sharedAccessToken: String? {
        SharedSessionKeychain(accessGroup: keychainAccessGroup).accessToken
    }

    /// An unexpanded `$(…)` or a placeholder counts as missing.
    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("$("),
              !value.hasPrefix("REPLACE_WITH_") else { return nil }
        return value
    }
}
