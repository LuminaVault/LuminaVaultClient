// LuminaVaultClient/LuminaVaultClient/Features/Settings/HermesGateways/HermesGatewaysPaneViewModel.swift
//
// HER-241 — list of supported Hermes messaging gateways (Telegram,
// Discord, Slack, WhatsApp). The server returns one row per gateway
// even when the user has no stored config; the view shows status badges
// and a chevron to the per-gateway detail screen.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class HermesGatewaysPaneViewModel {
    enum State: Equatable, Sendable {
        case loading
        case loaded(items: [HermesGatewayCatalogEntry])
        case error(message: String)
    }

    var state: State = .loading

    private let client: any HermesGatewaysClientProtocol

    init(client: any HermesGatewaysClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            let response = try await client.list()
            state = .loaded(items: response.items)
        } catch {
            state = .error(message: Self.errorMessage(error))
        }
    }

    func refresh() async {
        // Same as load but does not flip back to .loading so the list
        // doesn't flash empty on a swipe-down refresh.
        do {
            let response = try await client.list()
            state = .loaded(items: response.items)
        } catch {
            state = .error(message: Self.errorMessage(error))
        }
    }

    private static func errorMessage(_ error: any Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}

extension HermesGatewayStatus {
    var connectionHealth: ConnectionHealth {
        switch self {
        case .verified: .connected
        case .configured: .degraded
        case .error: .error
        case .notConfigured: .needsSetup
        }
    }

    var displayLabel: String {
        switch self {
        case .notConfigured: "Not connected"
        case .configured: "Configured"
        case .verified: "Connected"
        case .error: "Error"
        }
    }
}
