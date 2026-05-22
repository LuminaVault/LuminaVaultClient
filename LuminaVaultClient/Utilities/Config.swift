// LuminaVaultClient/LuminaVaultClient/Utilities/Config.swift
import Foundation

enum AppEnvironment: String, CaseIterable, Identifiable {
    case local
    case dev
    case prod
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .local: return "Local"
        case .dev: return "Dev"
        case .prod: return "Prod"
        }
    }
    
    var apiBaseURL: URL {
        switch self {
        case .local: return URL(string: "http://localhost:8080")!
        case .dev: return URL(string: "https://api.dev.luminavault.com")!
        case .prod: return URL(string: "https://api.luminavault.com")!
        }
    }
}

enum Config {
    static var currentEnvironment: AppEnvironment {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: "appEnvironment"),
               let env = AppEnvironment(rawValue: rawValue) {
                return env
            }
            #if DEBUG
            return .local
            #else
            return .prod
            #endif
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appEnvironment")
        }
    }

    /// HER-262 — `BackendMode` is the user-facing selection persisted by
    /// the Settings → Server Connection screen. When set it overrides
    /// the build-time `AppEnvironment`. Re-read on every access so
    /// flipping the mode hot-swaps the URL the next HTTP call uses.
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

    /// HER-185 — RevenueCat public SDK key. Layered: `REVENUECAT_PUBLIC_KEY`
    /// env var (Debug scheme override) → `LV_RC_API_KEY` Info.plist key
    /// (xcconfig-injected for TestFlight/Release). Returns nil when neither
    /// is set; `BillingService` treats that as a soft failure and falls
    /// back to server-truth only.
    static var revenueCatPublicKey: String? {
        envString("REVENUECAT_PUBLIC_KEY") ?? infoString("LV_RC_API_KEY")
    }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }

    private static func envString(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key],
              !value.isEmpty else { return nil }
        return value
    }
}
