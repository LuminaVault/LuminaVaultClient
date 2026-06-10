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
        case .byo: "Point at your own self-hosted LuminaVault server."
        case .tailscale: "MagicDNS host on your tailnet."
        case .localhost: "127.0.0.1 for dev rigs."
        }
    }

    /// Default URL for the mode. `.byo` resolves to the user-entered
    /// self-hosted server URL (`BYOServerStore`) and `.tailscale` to the
    /// user-entered tailnet host (`TailscaleServerStore`); when neither is
    /// set yet we fall back to the hosted URL so the app never points at nil.
    var defaultBaseURL: URL {
        switch self {
        case .hosted: return Config.hostedAPIBaseURL
        case .byo: return BYOServerStore.url ?? Config.hostedAPIBaseURL
        case .tailscale: return TailscaleServerStore.url ?? Config.hostedAPIBaseURL
        case .localhost: return URL(string: "http://localhost:8080")!
        }
    }
}

/// Persists the user-entered base URL for `.byo` (self-hosted LuminaVault
/// server) mode. The URL is not a secret, so UserDefaults is sufficient —
/// the bearer token earned by logging in against that server still lives in
/// the keychain like any other session.
enum BYOServerStore {
    static let userDefaultsKey = "lv.serverConnection.byoBaseURL"

    static var url: URL? {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              !raw.isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }

    /// Pass a trimmed `http(s)://host` string, or `nil` to clear.
    static func set(_ raw: String?) {
        UserDefaults.standard.set(raw, forKey: userDefaultsKey)
    }
}

/// Persists the user-entered tailnet host for `.tailscale` mode — a MagicDNS
/// name or tailnet IP for a LuminaVault server reachable over the user's
/// Tailscale network (e.g. `http://vault.tailnet-name.ts.net:8080`). iOS does
/// not expose tailnet state to apps, so the host is entered manually. Same
/// secrecy rationale as `BYOServerStore`: the URL is not a secret, the session
/// bearer stays in the keychain. WireGuard provides transport encryption, so
/// plain `http://` over the tailnet is acceptable here.
enum TailscaleServerStore {
    static let userDefaultsKey = "lv.serverConnection.tailscaleBaseURL"

    static var url: URL? {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              !raw.isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }

    /// Pass a trimmed `http(s)://host` string, or `nil` to clear.
    static func set(_ raw: String?) {
        UserDefaults.standard.set(raw, forKey: userDefaultsKey)
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
