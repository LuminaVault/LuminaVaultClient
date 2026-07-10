// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/GatewaysSetupView.swift
//
// HER-241 — optional onboarding step. 2-column grid of supported
// gateways (Telegram, Discord, Slack, WhatsApp). Tapping a card pushes
// the same `HermesGatewayDetailView` that powers the Settings pane;
// "Continue" advances the onboarding coordinator past the step.

import LuminaVaultShared
import SwiftUI

struct GatewaysSetupView: View {
    @State private var viewModel: GatewaysSetupViewModel
    let client: any HermesGatewaysClientProtocol

    init(viewModel: GatewaysSetupViewModel, client: any HermesGatewaysClientProtocol) {
        self.client = client
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            content

            Spacer(minLength: 0)

            footer
        }
        .padding(.top, 24)
        .task { await viewModel.onAppear() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            LVIconView(.bubbleLeftAndBubbleRightFill, size: 44, tint: .accentColor)
                .accessibilityHidden(true)
            Text("Connect a messaging app")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Chat with Lumina from Telegram, Discord, Slack, or WhatsApp. You can wire more later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().padding(.top, 24)
        case let .loaded(items):
            grid(items: items)
        case let .error(message):
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func grid(items: [HermesGatewayCatalogEntry]) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { entry in
                NavigationLink {
                    HermesGatewayDetailView(gatewayID: entry.id, client: client)
                } label: {
                    card(entry: entry)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    viewModel.didOpenGateway(entry.id)
                })
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func card(entry: HermesGatewayCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // HER-291: kept as Image — runtime symbol name
                Image(systemName: icon(for: entry.id))
                    .font(.title2)
                    .foregroundStyle(.tint)
                Spacer()
                ConnectionHealthBadge(health: entry.status.connectionHealth)
            }
            Text(entry.displayName).font(.headline)
            Text(entry.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        case .photon: "message.fill"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Button(viewModel.hasAnyConnected ? "Continue →" : "Skip for now") {
                if viewModel.hasAnyConnected {
                    viewModel.continueTapped()
                } else {
                    viewModel.skipTapped()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            if viewModel.hasAnyConnected {
                Button("Skip the rest") { viewModel.skipTapped() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }

            Text("You can wire more gateways later in Settings → Messaging Gateways.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }
}
