// LuminaVaultClient/LuminaVaultClient/Features/Settings/AccountPrivacyView.swift
import SwiftUI

struct AccountPrivacyView: View {
    @Environment(\.lvPalette) private var palette
    @State private var viewModel: AccountPrivacyViewModel

    init(viewModel: AccountPrivacyViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if viewModel.profile == nil, case .loading = viewModel.state {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } else {
                accountSection
                privacySection
                memorySection
            }

            if viewModel.isSaving {
                Section {
                    ProgressView("Saving")
                }
            }

            if case let .failed(message) = viewModel.state {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await viewModel.load() }
                    }
                }
            }
        }
        .navigationTitle("Account Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.profile == nil {
                await viewModel.load()
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if !viewModel.username.isEmpty {
                LabeledContent("Username", value: viewModel.username)
            }
            if !viewModel.email.isEmpty {
                LabeledContent("Email", value: viewModel.email)
            }
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Hide non-Canadian model origin", isOn: binding(
                get: { viewModel.privacyNoCNOrigin },
                set: { await viewModel.setPrivacyNoCNOrigin($0) }
            ))
            Toggle("Context routing", isOn: binding(
                get: { viewModel.contextRouting },
                set: { await viewModel.setContextRouting($0) }
            ))
            Toggle("Auto-save links", isOn: binding(
                get: { viewModel.autoSaveLinks },
                set: { await viewModel.setAutoSaveLinks($0) }
            ))
        } footer: {
            Text("These settings control server-side account privacy and capture behavior for your signed-in account.")
                .foregroundStyle(palette.textSecondary)
        }
        .disabled(viewModel.isSaving)
    }

    private var memorySection: some View {
        Section {
            Toggle("Mnemosyne memory", isOn: binding(
                get: { viewModel.mnemosyneEnabled },
                set: { await viewModel.setMnemosyneEnabled($0) }
            ))
        } footer: {
            Text("Changes apply to the managed Hermes container the next time it restarts.")
                .foregroundStyle(palette.textSecondary)
        }
        .disabled(viewModel.isSaving)
    }

    private func binding(
        get: @escaping () -> Bool,
        set: @escaping (Bool) async -> Void
    ) -> Binding<Bool> {
        Binding(
            get: get,
            set: { value in
                Task { await set(value) }
            }
        )
    }
}
