// LuminaVaultClient/LuminaVaultClient/Features/Settings/HermesGateways/HermesGatewaysPaneView.swift
//
// HER-241 — Settings → "Messaging Gateways" pane. Lists Telegram,
// Discord, Slack, WhatsApp with per-gateway connection status badges
// and chevrons into the detail screen.

import LuminaVaultShared
import SwiftUI

struct HermesGatewaysPaneView: View {
    @State private var viewModel: HermesGatewaysPaneViewModel
    let client: any HermesGatewaysClientProtocol

    init(client: any HermesGatewaysClientProtocol) {
        self.client = client
        _viewModel = State(initialValue: HermesGatewaysPaneViewModel(client: client))
    }

    var body: some View {
        List {
            switch viewModel.state {
            case .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case let .loaded(items):
                Section {
                    ForEach(items) { entry in
                        NavigationLink {
                            HermesGatewayDetailView(gatewayID: entry.id, client: client)
                        } label: {
                            row(for: entry)
                        }
                    }
                } footer: {
                    Text("Hermes runs the actual gateway processes on your host. LuminaVault stores the config encrypted and surfaces the CLI command to apply it.")
                }
            case let .error(message):
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Messaging Gateways")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
    private func row(for entry: HermesGatewayCatalogEntry) -> some View {
        HStack {
            Image(systemName: icon(for: entry.id))
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(.body)
                Text(entry.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            ConnectionBadge(state: entry.status.connectionState)
        }
        .padding(.vertical, 2)
    }

    private func icon(for id: HermesGatewayID) -> String {
        switch id {
        case .telegram: "paperplane.fill"
        case .discord: "gamecontroller.fill"
        case .slack: "number"
        case .whatsapp: "bubble.left.fill"
        }
    }
}
