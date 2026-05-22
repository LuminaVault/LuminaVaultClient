// LuminaVaultClient/LuminaVaultClient/Utilities/Config.swift
import Foundation

enum Config {
    /// HER-262 — `BackendMode` is the user-facing selection persisted by
    /// the Settings → Server Connection screen. Re-read on every access
    /// so flipping the mode hot-swaps the URL the next HTTP call uses.
    static var apiBaseURL: URL {
        BackendModeStore.current.defaultBaseURL
    }

    /// Provider client IDs are read from Info.plist keys so they can be
    /// injected per-environment via xcconfig / CI without committing real
    /// values to source. All return nil if unset — the corresponding sign-in
    /// service throws a user-visible "not configured" error in that case.
    static var appleServiceID: String? { infoString("APPLE_SERVICE_ID") }
    static var googleClientID: String? { infoString("GIDClientID") }
    static var googleReversedClientID: String? { infoString("GOOGLE_REVERSED_CLIENT_ID") }
    static var xClientID: String? { infoString("X_CLIENT_ID") }
    static var xRedirectURI: String? { infoString("X_REDIRECT_URI") }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }
}
