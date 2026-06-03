// LuminaVaultClient/LuminaVaultClient/Services/CalendarConnectService.swift
//
// HER-340 — drives the Google Calendar connect handoff. The server returns a
// Google consent URL; we open it in ASWebAuthenticationSession. Google
// redirects to the server's HTTPS callback (handled server-side), which then
// 303-redirects to `luminavault://oauth/google-calendar?status=ok|error`.
// ASWebAuthenticationSession intercepts that `luminavault://` scheme and
// returns the URL, which we parse for the outcome.

import AuthenticationServices
import Foundation

enum CalendarConnectError: LocalizedError {
    case cancelled
    case declined(String?)
    case badRedirect
    case session(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled: return nil
        case .declined(let reason):
            return reason.map { "Google declined the connection (\($0))." }
                ?? "Google declined the connection."
        case .badRedirect: return "Google returned an unexpected response. Please try again."
        case .session(let err): return err.localizedDescription
        }
    }
}

@MainActor
final class CalendarConnectService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let callbackScheme = "luminavault"

    private var anchor: ASPresentationAnchor?

    /// Open `authorizeURL` and await the app-scheme callback. Returns on
    /// `status=ok`; throws `CalendarConnectError` otherwise.
    func run(authorizeURL: URL, presentationAnchor: ASPresentationAnchor) async throws {
        anchor = presentationAnchor
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: Self.callbackScheme,
            ) { url, error in
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionError.errorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: CalendarConnectError.cancelled)
                    } else {
                        cont.resume(throwing: CalendarConnectError.session(error))
                    }
                    return
                }
                guard let url else {
                    cont.resume(throwing: CalendarConnectError.badRedirect)
                    return
                }
                cont.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        let status = items?.first { $0.name == "status" }?.value
        switch status {
        case "ok":
            return
        case "error":
            let reason = items?.first { $0.name == "reason" }?.value
            throw CalendarConnectError.declined(reason)
        default:
            throw CalendarConnectError.badRedirect
        }
    }

    nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor ?? ASPresentationAnchor() }
    }
}
