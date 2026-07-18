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
                summarySection(items: items)
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

    /// At-a-glance status dashboard: counts by gateway state + an alert when
    /// any gateway is in error.
    @ViewBuilder
    private func summarySection(items: [HermesGatewayCatalogEntry]) -> some View {
        let verified = items.filter { $0.status == .verified }.count
        let configured = items.filter { $0.status == .configured }.count
        let errored = items.filter { $0.status == .error }.count
        let off = items.filter { $0.status == .notConfigured }.count
        Section {
            HStack(alignment: .top) {
                stat("Verified", verified, .green)
                stat("Configured", configured, .blue)
                stat("Error", errored, .red)
                stat("Off", off, .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(LVSpacing.sm)
            .lvSigilFrame(cornerRadius: LVRadius.md)
            if errored > 0 {
                Label(
                    "\(errored) gateway\(errored == 1 ? "" : "s") need attention.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
        } header: {
            LVKickerLabel("Gateways / Everywhere you talk")
        }
    }

    private func stat(_ label: String, _ count: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title2.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func row(for entry: HermesGatewayCatalogEntry) -> some View {
        HStack {
            // HER-291: kept as Image — runtime symbol name
            Image(systemName: icon(for: entry.id))
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(.body)
                Text(entry.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            ConnectionHealthBadge(health: entry.status.connectionHealth)
        }
        .padding(.vertical, 2)
    }

    private func icon(for id: HermesGatewayID) -> String {
        switch id {
        case .telegram: "paperplane.fill"
        case .discord: "gamecontroller.fill"
        case .slack: "number"
        case .whatsapp: "bubble.left.fill"
        case .email: "envelope.fill"
        case .matrix: "circle.grid.cross.fill"
        case .ntfy: "bell.fill"
        case .mattermost: "bubble.left.and.bubble.right.fill"
        case .photon: "message.fill" // iMessage / Photon free path
        }
    }
}
