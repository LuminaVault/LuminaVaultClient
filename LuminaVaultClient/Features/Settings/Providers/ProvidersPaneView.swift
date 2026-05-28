// LuminaVaultClient/LuminaVaultClient/Features/Settings/Providers/ProvidersPaneView.swift
//
// HER-252 — Settings → Connections → LLM Providers entry point. Lists
// every supported provider; tap drills into ProviderEditSheet. The
// "Not configured" empty state is rendered inline so the list always
// has 5 rows of equal visual weight.

import LuminaVaultShared
import SwiftUI

struct ProvidersPaneView: View {
    @State private var viewModel: ProvidersPaneViewModel
    @State private var editingProvider: ProviderID?

    init(client: ProvidersClientProtocol) {
        _viewModel = State(initialValue: ProvidersPaneViewModel(client: client))
    }

    var body: some View {
        List {
            Section {
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    Button {
                        editingProvider = provider
                    } label: {
                        ProviderRowView(
                            provider: provider,
                            dto: viewModel.rows[provider],
                        )
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Falls back through your chain automatically when a provider runs out of credits or rate-limits.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("LLM Providers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(item: $editingProvider) { provider in
            ProviderEditSheet(
                provider: provider,
                existing: viewModel.rows[provider],
                onSave: { kind, key, url, label in
                    await viewModel.save(
                        provider: provider,
                        kind: kind,
                        apiKey: key,
                        baseUrl: url,
                        label: label,
                    )
                },
                onTest: {
                    await viewModel.test(provider: provider)
                    return viewModel.lastTestResult?.result
                },
                onDelete: {
                    await viewModel.delete(provider: provider)
                },
            )
        }
        .overlay(alignment: .bottom) {
            if let test = viewModel.lastTestResult {
                ProviderTestToast(result: test.result, providerName: ProvidersPaneViewModel.displayName(for: test.provider))
                    .padding()
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        if viewModel.lastTestResult?.provider == test.provider {
                            viewModel.lastTestResult = nil
                        }
                    }
            }
        }
    }
}

extension ProviderID: Identifiable {
    public var id: String { rawValue }
}

/// Inline toast for the Test Connection result. Replaced by the
/// app-wide toast system in a future pass.
struct ProviderTestToast: View {
    let result: ProvidersPaneViewModel.TestResult
    let providerName: String

    var body: some View {
        HStack(spacing: 8) {
            // HER-291: kept as Image — runtime symbol name
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .shadow(radius: 2)
    }

    private var icon: String {
        switch result {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch result {
        case .success: .green
        case .failure: .orange
        }
    }

    private var message: String {
        switch result {
        case let .success(model):
            if let model { return "\(providerName) verified (\(model))" }
            return "\(providerName) verified"
        case let .failure(code):
            return "\(providerName) failed — \(code)"
        }
    }
}
