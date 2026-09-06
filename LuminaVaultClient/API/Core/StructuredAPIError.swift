import Foundation

/// Server error envelope: `{ "error": { "code", "message", "cta"? } }`.
struct StructuredAPIError: Equatable, Sendable {
    let code: String
    let message: String
    let cta: [String]

    /// `message` is the only field required to be useful.
    ///
    /// This used to demand `code` as well, which meant every plain
    /// Hummingbird `HTTPError` — `{"error":{"message":"hermes_unreachable"}}`,
    /// and every `HTTPError(.badRequest, message:)` on the server — parsed as
    /// nil and was rendered as the useless "Server error (502)." The server
    /// was saying what was wrong the whole time; the client threw it away.
    /// Only the two hand-rolled envelopes carry `code`.
    ///
    /// `code` stays non-optional and empty when absent: it is used for
    /// behaviour (`chatRecoveryActions`), and an empty string simply matches
    /// nothing, which is the correct outcome for an envelope that named no
    /// code.
    static func parse(from data: Data) -> StructuredAPIError? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String,
            !message.isEmpty
        else {
            return nil
        }
        let cta = error["cta"] as? [String] ?? []
        return StructuredAPIError(code: error["code"] as? String ?? "", message: message, cta: cta)
    }
}

enum ChatRecoveryAction: Equatable, Sendable {
    case addKey
    case switchToManaged

    init?(ctaToken: String) {
        switch ctaToken {
        case "add_key": self = .addKey
        case "switch_to_managed": self = .switchToManaged
        default: return nil
        }
    }
}

extension APIError {
    var structuredError: StructuredAPIError? {
        guard case .httpError(_, let data) = self else { return nil }
        return StructuredAPIError.parse(from: data)
    }

    var userFacingMessage: String {
        if APIError.isBenignCancellation(self) {
            return "Something went wrong."
        }
        if let structured = structuredError {
            return structured.message
        }
        return errorDescription ?? "Something went wrong."
    }

    var chatRecoveryActions: [ChatRecoveryAction] {
        guard let structured = structuredError else { return [] }
        let actions = structured.cta.compactMap(ChatRecoveryAction.init)
        if !actions.isEmpty { return actions }
        // Older servers emit `byok_keys_required` (403) without a `cta`
        // array — the recovery paths are still exactly these two.
        if structured.code == "byok_keys_required" {
            return [.addKey, .switchToManaged]
        }
        return []
    }
}
