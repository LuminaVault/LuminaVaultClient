// LuminaVaultClient/LuminaVaultClient/API/Brief/BriefEndpoints.swift
//
// The daily brief as cards with an end.
//
// GET /v1/me/brief?date=yyyy-MM-dd — the day's brief, or `{"brief": null}`
// when there is none yet (not a 404). Without `date` the server answers for
// today in the user's own timezone, which is what Home and the
// `luminavault://brief` link both want.
//
// POST /v1/me/brief/{briefId}/cards/{cardId}/feedback {action} → 204 — one
// reaction per card per brief; a second one replaces the first.
//
// Both are the shared DTOs (`MeBriefResponse`, `BriefCardFeedbackRequest`);
// the server writes camelCase, which the default `.convertFromSnakeCase`
// decoder leaves untouched.

import Foundation
import LuminaVaultShared

nonisolated enum BriefEndpoints {
    nonisolated struct Get: Endpoint {
        typealias Response = MeBriefResponse
        /// `yyyy-MM-dd`. Nil lets the server pick today in the user's zone.
        let date: String?

        var path: String {
            guard let date else { return "/v1/me/brief" }
            return "/v1/me/brief?date=\(BriefEndpoints.pathSafe(date))"
        }

        var method: HTTPMethod {
            .get
        }

        /// Home loads this passively; a 402 hides the card rather than
        /// sliding a paywall over whatever the user was doing.
        var presentsPaywallOn402: Bool {
            false
        }
    }

    nonisolated struct Feedback: Endpoint {
        typealias Response = EmptyResponse
        let briefID: UUID
        /// The card's id within the brief — its kind, or `<kind>-2`.
        let cardID: String
        let action: BriefCardFeedbackAction

        var path: String {
            "/v1/me/brief/\(briefID.uuidString.lowercased())/cards/\(BriefEndpoints.pathSafe(cardID))/feedback"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            BriefCardFeedbackRequest(action: action)
        }

        /// A reaction is a tap inside a sheet the user already opened; the
        /// card shows its own error rather than a paywall.
        var presentsPaywallOn402: Bool {
            false
        }
    }

    /// Card ids are server-chosen (`openLoops`, `weather-2`); percent-encode
    /// anything that could break out of a path segment or a query value.
    static func pathSafe(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#&=+")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }
}
