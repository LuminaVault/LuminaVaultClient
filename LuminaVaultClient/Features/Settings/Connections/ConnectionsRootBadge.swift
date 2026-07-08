// LuminaVaultClient/LuminaVaultClient/Features/Settings/Connections/ConnectionsRootBadge.swift
import SwiftUI

struct ConnectionsRootBadge: View {
    @State private var state: ConnectionState = .unknown
    private let client: any ConnectionsClientProtocol

    init(client: any ConnectionsClientProtocol) {
        self.client = client
    }

    var body: some View {
        ConnectionBadge(state: state)
            .task { await load() }
    }

    private func load() async {
        do {
            let response = try await client.summary()
            state = response.connections.contains { $0.health == .error || $0.health == .degraded }
                ? .disconnected
                : .connected
        } catch {
            state = .unknown
        }
    }
}
