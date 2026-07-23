import Foundation

/// Server error envelope: `{ "error": { "code", "message", "cta"? } }`.
struct StructuredAPIError: Equatable, Sendable {
    let code: String
    let message: String
    let cta: [String]

    static func parse(from data: Data) -> StructuredAPIError? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let code = error["code"] as? String,
            let message = error["message"] as? String
        else {
            return nil
        }
        let cta = error["cta"] as? [String] ?? []
        return StructuredAPIError(code: code, message: message, cta: cta)
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
