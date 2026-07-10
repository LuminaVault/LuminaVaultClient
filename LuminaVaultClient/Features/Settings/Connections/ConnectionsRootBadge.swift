// LuminaVaultClient/LuminaVaultClient/Features/Settings/Connections/ConnectionsRootBadge.swift
import SwiftUI

struct ConnectionsRootBadge: View {
    @State private var health: ConnectionHealth = .unknown
    private let client: any ConnectionsClientProtocol

    init(client: any ConnectionsClientProtocol) {
        self.client = client
    }

    var body: some View {
        ConnectionHealthBadge(health: health)
            .task { await load() }
    }

    private func load() async {
        do {
            let response = try await client.summary()
            health = aggregateHealth(response.connections.map(\.health))
        } catch {
            health = .unknown
        }
    }

    private func aggregateHealth(_ values: [ConnectionHealth]) -> ConnectionHealth {
        if values.contains(.error) { return .error }
        if values.contains(.degraded) { return .degraded }
        if values.contains(.testing) { return .testing }
        if values.contains(.connected) { return .connected }
        if values.contains(.needsSetup) { return .needsSetup }
        if values.contains(.unknown) || values.isEmpty { return .unknown }
        return .connected
    }
}
