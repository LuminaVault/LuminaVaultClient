// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/GatewaysSetupViewModel.swift
//
// HER-241 — view model for the optional messaging gateways onboarding
// step. Same idempotent / no-server-state shape as BYOHermesPromptView
// (HER-219). Wraps the per-gateway list so the user can dip into each
// detail screen and return without losing the onboarding context.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class GatewaysSetupViewModel {
    enum Event {
        static let shown = "onboarding.gateways_setup.shown"
        static let openGateway = "onboarding.gateways_setup.open_gateway"
        static let continueTapped = "onboarding.gateways_setup.continue"
        static let skipped = "onboarding.gateways_setup.skipped"
    }

    enum State: Equatable, Sendable {
        case loading
        case loaded(items: [HermesGatewayCatalogEntry])
        case error(message: String)
    }

    var state: State = .loading

    private let telemetry: any TelemetryProtocol
    private let client: any HermesGatewaysClientProtocol
    private let onContinue: @MainActor () -> Void
    private let onSkip: @MainActor () -> Void

    private(set) var hasFiredShownEvent = false

    init(
        telemetry: any TelemetryProtocol,
        client: any HermesGatewaysClientProtocol,
        onContinue: @escaping @MainActor () -> Void,
        onSkip: @escaping @MainActor () -> Void,
    ) {
        self.telemetry = telemetry
        self.client = client
        self.onContinue = onContinue
        self.onSkip = onSkip
    }

    func onAppear() async {
        if !hasFiredShownEvent {
            hasFiredShownEvent = true
            telemetry.track(Event.shown)
        }
        await load()
    }

    func load() async {
        do {
            let response = try await client.list()
            state = .loaded(items: response.items)
        } catch {
            state = .error(message: (error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func didOpenGateway(_ id: HermesGatewayID) {
        telemetry.track(Event.openGateway, properties: ["gateway": id.rawValue])
    }

    func continueTapped() {
        let connected = countConnected()
        telemetry.track(Event.continueTapped, properties: ["connected_count": String(connected)])
        onContinue()
    }

    func skipTapped() {
        telemetry.track(Event.skipped)
        onSkip()
    }

    var connectedCount: Int { countConnected() }
    var hasAnyConnected: Bool { connectedCount > 0 }

    private func countConnected() -> Int {
        guard case let .loaded(items) = state else { return 0 }
        return items.filter { $0.hasConfig }.count
    }
}
