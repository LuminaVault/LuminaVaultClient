// LuminaVaultClient/LuminaVaultClient/Features/Settings/Connections/ConnectionsHubView.swift
import SwiftUI

struct ConnectionsHubView: View {
    @State private var viewModel: ConnectionsHubViewModel
    let automaticallyTest: Bool
    let destination: (ConnectionSummaryDTO) -> AnyView

    init(
        client: any ConnectionsClientProtocol,
        automaticallyTest: Bool = false,
        destination: @escaping (ConnectionSummaryDTO) -> AnyView
    ) {
        _viewModel = State(initialValue: ConnectionsHubViewModel(client: client))
        self.automaticallyTest = automaticallyTest
        self.destination = destination
    }

    var body: some View {
        List {
            Section {
                if viewModel.isLoading && viewModel.connections.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(viewModel.connections) { connection in
                        NavigationLink {
                            destination(connection)
                        } label: {
                            ConnectionSummaryRow(connection: connection)
                        }
                    }
                }
            } header: {
                Text("Connections")
            } footer: {
                if let checkedAt = viewModel.checkedAt {
                    Text("Checked \(checkedAt.formatted(.relative(presentation: .named))).")
                }
            }

            Section {
                Button {
                    Task { await viewModel.testAll() }
                } label: {
                    HStack {
                        Text("Test all connections")
                        Spacer()
                        if viewModel.isTesting {
                            ProgressView()
                        } else {
                            LVIconView(.arrowClockwise, size: 14, tint: .secondary)
                        }
                    }
                }
                .disabled(viewModel.isTesting)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Diagnostics")
            }

            if !viewModel.events.isEmpty {
                Section("Recent Events") {
                    ForEach(viewModel.events) { event in
                        ConnectionDiagnosticEventRow(event: event)
                    }
                }
            }
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .task {
            if automaticallyTest {
                await viewModel.testAll()
            } else {
                await viewModel.load()
            }
        }
    }
}

struct ConnectionSummaryRow: View {
    let connection: ConnectionSummaryDTO

    var body: some View {
        HStack(spacing: LVSpacing.base) {
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.title)
                    .font(LVTypography.bodyEmphasis.font)
                if let subtitle = connection.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(LVTypography.caption.font)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let detail = connection.statusDetail, !detail.isEmpty {
                    Text(detail)
                        .font(LVTypography.caption.font)
                        .foregroundStyle(connection.health.tint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: LVSpacing.sm)

            ConnectionHealthBadge(health: connection.health)
        }
        .padding(.vertical, LVSpacing.xs)
    }
}

private struct ConnectionDiagnosticEventRow: View {
    let event: ConnectionDiagnosticEventDTO

    var body: some View {
        HStack(alignment: .top, spacing: LVSpacing.base) {
            Circle()
                .fill(event.severity.tint)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.connectionTitle ?? event.connectionID ?? "Connection")
                    .font(LVTypography.caption.font.weight(.semibold))
                Text(event.message)
                    .font(LVTypography.caption.font)
                    .foregroundStyle(.secondary)
                Text(event.occurredAt.formatted(.relative(presentation: .named)))
                    .font(LVTypography.caption.font)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private extension ConnectionDiagnosticSeverity {
    var tint: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}
