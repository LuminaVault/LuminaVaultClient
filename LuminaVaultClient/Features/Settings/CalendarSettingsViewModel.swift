// LuminaVaultClient/LuminaVaultClient/Features/Settings/CalendarSettingsViewModel.swift
//
// HER-340 — Google Calendar settings pane state. Connect runs the OAuth
// handoff (CalendarConnectService); status + upcoming events come from the
// server cache. Event creation is the explicit "Add to Calendar" action.

import AuthenticationServices
import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class CalendarSettingsViewModel {
    enum State: Sendable {
        case loading
        case ready(CalendarStatusResponse)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var events: [CalendarEventDTO] = []
    var isWorking = false
    var lastError: String?

    private let client: any CalendarClientProtocol
    private let connectService: CalendarConnectService

    init(client: any CalendarClientProtocol = CalendarHTTPClient(),
         connectService: CalendarConnectService = CalendarConnectService()) {
        self.client = client
        self.connectService = connectService
    }

    var isConnected: Bool {
        if case let .ready(status) = state { return status.connected }
        return false
    }

    func load() async {
        state = .loading
        do {
            let status = try await client.status()
            state = .ready(status)
            if status.connected {
                events = (try? await client.events().events) ?? []
            } else {
                events = []
            }
        } catch {
            state = .failed(Self.message(error))
        }
    }

    func connect(anchor: ASPresentationAnchor) async {
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
            try await connectService.run(authorizeURL: url, presentationAnchor: anchor)
            await load()
        } catch CalendarConnectError.cancelled {
            // User dismissed the browser — no error banner.
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

    func addEvent(title: String, startsAt: Date, endsAt: Date, location: String?, notes: String?) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let request = CalendarCreateEventRequest(
                title: title,
                startsAt: startsAt,
                endsAt: endsAt,
                location: location?.isEmpty == true ? nil : location,
                notes: notes?.isEmpty == true ? nil : notes,
                attendees: nil,
            )
            _ = try await client.createEvent(request)
            events = (try? await client.events().events) ?? events
            return true
        } catch {
            lastError = Self.message(error)
            return false
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
