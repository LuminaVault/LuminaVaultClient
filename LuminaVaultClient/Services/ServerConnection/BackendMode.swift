// LuminaVaultClient/LuminaVaultClient/Services/ServerConnection/BackendMode.swift
//
// HER-250 / HER-262 — backend mode is the user-facing selection
// (Hosted / BYO / Tailscale / Localhost). HER-262 promotes it from a
// view-local enum to a shared service so `Config.apiBaseURL` can read
// it and `Notification` observers can react to flips without an app
// restart.

import Foundation

enum BackendMode: String, CaseIterable, Identifiable, Sendable {
    case hosted
    case byo
    case tailscale
    case localhost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hosted: "Hosted"
        case .byo: "BYO endpoint"
        case .tailscale: "Tailscale"
        case .localhost: "Localhost dev"
        }
    }

    var subtitle: String {
        switch self {
        case .hosted: "luminavault.example managed instance."
        case .byo: "Your own Hermes URL (HER-218)."
        case .tailscale: "MagicDNS host on your tailnet."
        case .localhost: "127.0.0.1 for dev rigs."
        }
    }

    /// Default URL for the mode. BYO / Tailscale fall through to the
    /// dedicated Hermes Gateway override (HER-218) which is the
    /// source of truth for custom hosts; we surface the hosted URL
    /// here as a sensible fallback when the override isn't set.
    var defaultBaseURL: URL {
        switch self {
        case .hosted: return Config.hostedAPIBaseURL
        case .byo: return Config.hostedAPIBaseURL
        case .tailscale: return Config.hostedAPIBaseURL
        case .localhost: return URL(string: "http://localhost:8080")!
        }
    }
}

enum BackendModeStore {
    static let userDefaultsKey = "lv.serverConnection.backendMode"

    /// HER-262 — posted by `ServerConnectionViewModel.setMode`. Active
    /// screens listen for this and re-fetch against the new base URL.
    static let modeChangedNotification = Notification.Name("lv.backendMode.changed")

    static var current: BackendMode {
        if let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
           let mode = BackendMode(rawValue: raw) {
            return mode
        }
        #if DEBUG
        return .localhost
        #else
        return .hosted
        #endif
    }

    static func set(_ newMode: BackendMode) {
        UserDefaults.standard.set(newMode.rawValue, forKey: userDefaultsKey)
        NotificationCenter.default.post(name: modeChangedNotification, object: newMode)
    }
}
