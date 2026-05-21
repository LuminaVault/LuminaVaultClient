// LuminaVaultClient/LuminaVaultClient/Features/Settings/LLMPreferences/LLMPreferencesPaneView.swift
//
// HER-252 — Settings → Advanced → Model Preferences. Picks the user's
// primary (provider, model) and an ordered fallback chain. Free-form
// model TextField for now; provider-specific autocomplete is a
// follow-up.

import LuminaVaultShared
import SwiftUI

struct LLMPreferencesPaneView: View {
    @State private var viewModel: LLMPreferencesPaneViewModel

    init(client: LLMPreferencesClientProtocol) {
        _viewModel = State(initialValue: LLMPreferencesPaneViewModel(client: client))
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: Binding(
                    get: { viewModel.primaryProvider },
                    set: { newValue in
                        viewModel.primaryProvider = newValue
                        viewModel.markDirty()
                    },
                )) {
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        Text(ProvidersPaneViewModel.displayName(for: provider)).tag(provider)
                    }
                }
                TextField("Model", text: Binding(
                    get: { viewModel.primaryModel },
                    set: { newValue in
                        viewModel.primaryModel = newValue
                        viewModel.markDirty()
                    },
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            } header: {
                Text("Primary")
            } footer: {
                Text("Tried first on every chat / query / kb-compile call.")
                    .font(.footnote)
            }

            Section {
                FallbackChainEditor(viewModel: viewModel)
                Button {
                    viewModel.addFallback()
                } label: {
                    Label("Add fallback", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Fallback chain")
            } footer: {
                Text("Walked in order when the primary returns credit-exhausted, rate-limit, or upstream-error.")
                    .font(.footnote)
            }

            Section {
                Button {
                    Task { await viewModel.save() }
                } label: {
                    HStack {
                        Spacer()
                        Text("Save")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!viewModel.hasUnsavedChanges || viewModel.primaryModel.isEmpty)
            }

            if case let .failed(message) = viewModel.state {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Model Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }
}

struct FallbackChainEditor: View {
    @Bindable var viewModel: LLMPreferencesPaneViewModel

    var body: some View {
        ForEach(Array(viewModel.fallbackChain.enumerated()), id: \.offset) { index, step in
            HStack {
                Picker("", selection: Binding(
                    get: { step.provider },
                    set: { viewModel.updateFallback(at: index, provider: $0) },
                )) {
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        Text(ProvidersPaneViewModel.displayName(for: provider)).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)

                TextField("Model", text: Binding(
                    get: { step.model },
                    set: { viewModel.updateFallback(at: index, model: $0) },
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
        }
        .onDelete { offsets in
            viewModel.removeFallback(at: offsets)
        }
        .onMove { from, to in
            viewModel.moveFallback(from: from, to: to)
        }
    }
}
