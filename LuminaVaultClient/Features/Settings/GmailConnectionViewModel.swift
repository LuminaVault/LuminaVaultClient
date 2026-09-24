// LuminaVaultClient/LuminaVaultClient/Features/Settings/GmailConnectionViewModel.swift
//
// Muse Stage C — Settings → Linked Accounts → Gmail. Mirrors
// `CalendarSettingsViewModel`: the server hands back a Google consent URL, the
// OAuth handoff runs in ASWebAuthenticationSession (`CalendarConnectService`,
// which already parses the `luminavault://oauth/google-gmail?status=…`
// callback), then status is re-read. The handoff is injected so tests never
// open a browser.

import AuthenticationServices
import Foundation
import LuminaVaultShared
import UIKit

@Observable
@MainActor
final class GmailConnectionViewModel {
    enum State: Equatable, Sendable {
        case loading
        case ready(GmailStatusResponse)
        case failed(String)
    }

    /// Opens the consent URL and returns once the app-scheme callback says
    /// `status=ok`; throws `CalendarConnectError` otherwise.
    typealias Handoff = @MainActor (URL) async throws -> Void

    /// What Hermie reads, stated wherever Gmail can be turned on.
    static let privacyLine = "Hermie reads sender, subject and a snippet; never message bodies."

    private(set) var state: State = .loading
    private(set) var isWorking = false
    private(set) var lastError: String?

    private let client: any GmailClientProtocol
    private let handoff: Handoff

    init(client: any GmailClientProtocol, handoff: Handoff? = nil) {
        self.client = client
        self.handoff = handoff ?? Self.browserHandoff()
    }

    var status: GmailStatusResponse? {
        if case let .ready(status) = state { return status }
        return nil
    }

    /// Connected and usable. A grant Google has rejected is not.
    var isConnected: Bool { status.map { $0.connected && !$0.needsReauth } ?? false }
    var needsReauth: Bool { status?.needsReauth ?? false }

    var statusText: String {
        guard let status else { return "—" }
        if status.needsReauth { return "Reconnect needed" }
        return status.connected ? "Connected" : "Not connected"
    }

    /// The row's primary action, when it has one.
    var connectLabel: String? {
        guard let status else { return nil }
        if status.needsReauth { return "Reconnect Gmail" }
        return status.connected ? nil : "Connect Gmail"
    }

    /// Disconnecting Gmail leaves Calendar alone when the same Google account
    /// grants both, so say which will happen.
    var disconnectMessage: String {
        if status?.calendarConnected == true {
            return "Hermie stops reading your inbox. Google Calendar stays connected."
        }
        return "Revokes Hermie's access to your Gmail. You can reconnect any time."
    }

    func load() async {
        if status == nil { state = .loading }
        do {
            state = .ready(try await client.status())
        } catch is CancellationError {
            return
        } catch {
            state = .failed(Self.message(error))
        }
    }

    func connect() async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let start = try await client.connect()
            guard let url = URL(string: start.authorizeURL) else {
                lastError = "Invalid authorization URL from server."
                return
            }
            try await handoff(url)
            await load()
        } catch CalendarConnectError.cancelled {
            // The user closed the browser — not an error worth a banner.
        } catch {
            lastError = Self.message(error)
        }
    }

    func disconnect() async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await client.disconnect()
            await load()
        } catch {
            lastError = Self.message(error)
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// The real handoff: ASWebAuthenticationSession anchored on the key window.
    private static func browserHandoff() -> Handoff {
        let service = CalendarConnectService()
        return { url in
            let scene = UIApplication.shared.connectedScenes
                .first { $0.activationState == .foregroundActive } as? UIWindowScene
            let anchor = scene?.keyWindow ?? ASPresentationAnchor()
            try await service.run(authorizeURL: url, presentationAnchor: anchor)
        }
    }
}
