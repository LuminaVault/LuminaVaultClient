// LuminaVaultClient/LuminaVaultClient/Utilities/Config.swift
import Foundation

enum Config {
    /// HER-262 — `BackendMode` is the user-facing selection persisted by
    /// the Settings → Server Connection screen. Re-read on every access
    /// so flipping the mode hot-swaps the URL the next HTTP call uses.
    static var apiBaseURL: URL {
        BackendModeStore.current.defaultBaseURL
    }

    static var hostedAPIBaseURL: URL {
        URL(string: infoString("API_BASE_URL") ?? "https://api.luminavault.com")!
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
    /// HER-216 — WebAuthn relying-party identifier. MUST match the `id`
    /// returned in the server's `rp` block (usually the apex domain — e.g.
    /// `luminavault.app`). Pair with an `associated-domains` entitlement
    /// of `webcredentials:<this-value>` for the OS to honour cross-device
    /// passkey sync via iCloud Keychain.
    static var webAuthnRelyingPartyID: String? { infoString("WEBAUTHN_RP_ID") }
    static var sentryDSN: String? { envString("SENTRY_DSN") ?? infoString("SENTRY_DSN") }
    static var sentryEnvironment: String? { envString("SENTRY_ENVIRONMENT") ?? infoString("SENTRY_ENVIRONMENT") }

    /// HER-185 — RevenueCat public SDK key. Layered: `REVENUECAT_PUBLIC_KEY`
    /// env var (Debug scheme override) → `LV_RC_API_KEY` Info.plist key
    /// (xcconfig-injected for TestFlight/Release). Returns nil when neither
    /// is set; `BillingService` treats that as a soft failure and falls
    /// back to server-truth only.
    static var revenueCatPublicKey: String? {
        envString("REVENUECAT_PUBLIC_KEY") ?? infoString("LV_RC_API_KEY")
    }

    /// HER-188 — App Review-required legal links surfaced from the
    /// Settings Subscription pane and (transitively) the paywall.
    /// Defaults point at production luminavault.com but can be overridden
    /// per-environment via Info.plist keys `LV_TERMS_URL` / `LV_PRIVACY_URL`.
    static var termsOfServiceURL: URL {
        URL(string: infoString("LV_TERMS_URL") ?? "https://luminavault.com/terms")!
    }

    static var privacyPolicyURL: URL {
        URL(string: infoString("LV_PRIVACY_URL") ?? "https://luminavault.com/privacy")!
    }

    /// HER-298 — social handles surfaced from Settings → About. Placeholder
    /// `@luminavault` defaults until real accounts are claimed; each is
    /// Info.plist-overridable so staging vs prod can point elsewhere.
    static var tiktokURL: URL {
        URL(string: infoString("LV_TIKTOK_URL") ?? "https://www.tiktok.com/@luminavault")!
    }

    static var xProfileURL: URL {
        URL(string: infoString("LV_X_PROFILE_URL") ?? "https://x.com/luminavault")!
    }

    static var instagramURL: URL {
        URL(string: infoString("LV_INSTAGRAM_URL") ?? "https://instagram.com/luminavault")!
    }

    /// HER-298 — brand + support links surfaced from Settings → About.
    static var websiteURL: URL {
        URL(string: infoString("LV_WEBSITE_URL") ?? "https://luminavault.com")!
    }

    static var supportEmail: String {
        infoString("LV_SUPPORT_EMAIL") ?? "support@luminavault.com"
    }

    /// HER-298 — derived version string for the About pane. Reads
    /// `CFBundleShortVersionString` + `CFBundleVersion` directly from the
    /// app bundle so a single source updates every surface that shows the
    /// version. Falls back to "v0.0.0 (build 0)" when both keys are
    /// missing (only possible in unit-test bundles that ship without an
    /// Info.plist).
    static var appVersionString: String {
        let short = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
        return "v\(short) (build \(build))"
    }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("$("),
              !value.hasPrefix("REPLACE_WITH_") else { return nil }
        return value
    }

    private static func envString(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key],
              !value.isEmpty else { return nil }
        return value
    }
}
