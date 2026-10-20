// LuminaVaultClient/LuminaVaultClient/API/Learned/LearnedEndpoints.swift
//
// GET /v1/me/learned?since=<ISO8601> — what Lumina picked up about the user
// that they have not confirmed yet: proposed SOUL.md changes and new
// preference / decision memories. Without `since` the server answers for the
// last seven days.
//
// The response is the shared `LearnedDigestResponse`; the server writes
// camelCase, which the default `.convertFromSnakeCase` decoder leaves
// untouched. Keep / forget go through the existing endpoints — see
// `LearnedThisWeekViewModel`.

import Foundation
import LuminaVaultShared

nonisolated enum LearnedEndpoints {
    nonisolated struct Get: Endpoint {
        typealias Response = LearnedDigestResponse
        /// Nil lets the server pick its default window (the last 7 days).
        let since: Date?

        var path: String {
            guard let since else { return "/v1/me/learned" }
            return "/v1/me/learned?since=\(Self.queryValue(for: since))"
        }

        var method: HTTPMethod {
            .get
        }

        /// Home loads this passively; a 402 hides the row rather than
        /// sliding a paywall over whatever the user was doing.
        var presentsPaywallOn402: Bool {
            false
        }

        /// `2026-10-09T08:30:00Z` — UTC, whole seconds. Percent-encoded with
        /// `+` excluded too, so an offset form could never read as a space.
        static func queryValue(for date: Date) -> String {
            let raw = date.formatted(.iso8601)
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "+&=")
            return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
        }
    }
}
