// LuminaVaultClient/LuminaVaultClient/API/Hermes/HermesRunsFailure.swift
//
// Hermes Companion Phase 1 — the stable error codes `/v1/hermes/runs`
// returns, mapped to something a screen can say out loud.
//
// The server answers failures as `HTTPError(status, message: <stable code>)`,
// which Hummingbird serialises as `{"error":{"message":"hermes_runs_unsupported"}}`.
// That envelope carries no `code` key, so `StructuredAPIError` (which requires
// one) does not match it — the stable code lives in `error.message`. This
// type is the one place that knows that.
//
// The distinction that matters most: a 501 `hermes_runs_unsupported` means
// the user's own Hermes is too old to serve `/v1/runs`. That is a fixable
// setup problem with a specific remedy, not "something went wrong", and the
// UI must say so.

import Foundation

enum HermesRunsFailure: Equatable, Sendable {
    /// 501 — this tenant's Hermes predates `/v1/runs`. Retrying cannot help.
    case unsupported
    /// 410 — Hermes dropped the run from its 300 s in-memory store. The
    /// persisted transcript survives; only live control is gone.
    case expired
    /// 409 — the approval was already answered (often from another device,
    /// or from the notification itself).
    case approvalNotPending
    /// 409 — stop arrived after the run had already finished.
    case runNotActive
    /// 429 — too many runs in flight for this tenant.
    case tooManyRuns
    /// 502 — Hermes was reachable but errored.
    case upstream
    /// 400 — empty prompt.
    case promptRequired
    /// 404 — no such run for this tenant.
    case notFound
    case unauthorized
    /// Transport-level: offline, DNS, TLS.
    case offline
    case unknown(String)

    /// Maps any error thrown by `HermesRunsClientProtocol` onto a case.
    /// Non-`APIError` values (including `CancellationError`) fall through to
    /// `.unknown`; call sites drop cooperative cancels before they get here.
    init(_ error: any Error) {
        guard let apiError = error as? APIError else {
            self = .unknown(error.localizedDescription)
            return
        }
        switch apiError {
        case .unauthorized:
            self = .unauthorized
        case .rateLimited:
            // `BaseHTTPClient` converts every 429 before the body is read, so
            // `hermes_runs_limit` only ever reaches us in this shape.
            self = .tooManyRuns
        case .networkFailure, .tlsPinningFailed:
            self = .offline
        case .httpError(let status, let data):
            self = Self.fromHTTP(status: status, data: data)
        default:
            self = .unknown(apiError.userFacingMessage)
        }
    }

    private static func fromHTTP(status: Int, data: Data) -> HermesRunsFailure {
        switch Self.stableCode(in: data) {
        case "hermes_runs_unsupported": return .unsupported
        case "hermes_run_expired": return .expired
        case "hermes_approval_not_pending": return .approvalNotPending
        case "hermes_run_not_active": return .runNotActive
        case "hermes_runs_limit": return .tooManyRuns
        case "prompt_required": return .promptRequired
        case "hermes_run_not_found": return .notFound
        case let code? where code.hasPrefix("hermes_runs_"): return .upstream
        default: break
        }
        // No recognised code — fall back to the status line, which is still
        // meaningful because the server maps each family to a fixed status.
        switch status {
        case 400: return .promptRequired
        case 401: return .unauthorized
        case 404: return .notFound
        case 409: return .approvalNotPending
        case 410: return .expired
        case 429: return .tooManyRuns
        case 501: return .unsupported
        case 502, 503, 504: return .upstream
        default: return .unknown("Server error (\(status)).")
        }
    }

    /// Reads `{"error":{"message":"<code>"}}`.
    private static func stableCode(in data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return nil
        }
        return message
    }

    /// One sentence, safe on a card or in a toast.
    var message: String {
        switch self {
        case .unsupported:
            return "Your Hermes is too old to run agents from the app."
        case .expired:
            return "Hermes has already forgotten this run — you can still read the transcript."
        case .approvalNotPending:
            return "That approval was already answered."
        case .runNotActive:
            return "This run had already finished."
        case .tooManyRuns:
            return "Too many runs going at once. Wait for one to finish."
        case .upstream:
            return "Your Hermes couldn't be reached."
        case .promptRequired:
            return "Say what you want Hermes to do."
        case .notFound:
            return "That run no longer exists."
        case .unauthorized:
            return "Session expired — sign in again."
        case .offline:
            return "You're offline."
        case .unknown(let text):
            return text
        }
    }

    /// The remedy, when there is a concrete one. Rendered under `message`.
    var guidance: String? {
        switch self {
        case .unsupported:
            return "Update Hermes to a build that serves /v1/runs, then try again."
        case .upstream:
            return "Check that your Hermes is online in Settings → Hermes."
        case .offline:
            return "Reconnect and try again."
        default:
            return nil
        }
    }

    /// False where retrying the exact same call cannot possibly succeed.
    /// Drives whether a screen shows a "Try again" button.
    var isRetryable: Bool {
        switch self {
        case .unsupported, .promptRequired, .notFound, .approvalNotPending, .runNotActive:
            return false
        case .expired, .tooManyRuns, .upstream, .unauthorized, .offline, .unknown:
            return true
        }
    }
}
