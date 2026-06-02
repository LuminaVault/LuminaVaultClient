// LuminaVaultClient/LuminaVaultClient/Utilities/URLValidation.swift
//
// Shared base-URL validation + transport-security heuristics. Extracted so
// both the Hermes Gateway pane (HER-218) and the BYO LuminaVault server
// picker classify URLs the same way instead of duplicating the logic.

import Foundation

enum URLValidation {
    /// True when `raw` parses to an http/https URL with a non-empty host.
    static func isValidBaseURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return false }
        let scheme = url.scheme?.lowercased()
        return (scheme == "https" || scheme == "http") && (url.host?.isEmpty == false)
    }

    /// Non-nil when the URL trades away transport security: `http://` sends
    /// the auth token in plaintext, and a bare IP can't present a valid TLS
    /// certificate. Shown as a caution banner; not a hard block.
    static func transportWarning(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            return nil
        }
        if url.scheme?.lowercased() == "http" {
            return "No TLS — your auth token and traffic are sent in plaintext over http://. "
                + "Use https:// with a domain whenever possible."
        }
        if isBareIP(host) {
            return "Raw IP address — there's no certificate to validate, so the connection "
                + "can't be authenticated. A domain + HTTPS is safer."
        }
        return nil
    }

    /// Detects a bare IPv4/IPv6 literal host (no domain). IPv6 hosts from
    /// `URL.host` may arrive bracket-stripped; a `:` is a sufficient tell.
    static func isBareIP(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part) else { return false }
            return (0 ... 255).contains(n)
        }
    }
}
