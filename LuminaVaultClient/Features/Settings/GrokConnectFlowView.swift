// LuminaVaultClient/LuminaVaultClient/Features/Settings/GrokConnectFlowView.swift
//
// HER-240b — SwiftUI sheet that hosts the Grok OAuth flow.

import SwiftUI

struct GrokConnectFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GrokConnectFlowViewModel
    let onConnected: (XaiStatusResponse) -> Void

    init(client: any IntegrationsClientProtocol, onConnected: @escaping (XaiStatusResponse) -> Void) {
        _viewModel = State(initialValue: GrokConnectFlowViewModel(client: client))
        self.onConnected = onConnected
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Connect xAI Grok")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") {
                            viewModel.cancel()
                            dismiss()
                        }
                    }
                }
        }
        .task(id: ObjectIdentifier(viewModel)) {
            if case .idle = viewModel.state {
                await viewModel.start()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .starting:
            VStack(spacing: 12) {
                ProgressView()
                Text("Preparing xAI sign-in…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .awaitingCallback(_, url):
            GrokOAuthWebView(
                authorizeURL: url,
                onCallback: { captured in
                    Task { await viewModel.submitCallback(captured) }
                },
                onError: { _ in
                    viewModel.cancel()
                },
            )
            .ignoresSafeArea()
        case .completing:
            VStack(spacing: 12) {
                ProgressView()
                Text("Finishing up…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .success(status):
            VStack(spacing: 20) {
                LVIconView(.checkmarkSealFill, size: 56, tint: .green)
                Text("Connected").font(.title2.bold())
                Text("Tier: \(status.tier)").foregroundStyle(.secondary)
                Button("Done") {
                    onConnected(status)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        case let .failed(message):
            VStack(spacing: 20) {
                LVIconView(.exclamationmarkTriangleFill, size: 56, tint: .orange)
                Text("Couldn't connect").font(.title2.bold())
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
    }
}
