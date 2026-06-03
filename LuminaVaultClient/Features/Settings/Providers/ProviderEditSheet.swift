// LuminaVaultClient/LuminaVaultClient/Features/Settings/Providers/ProviderEditSheet.swift
//
// HER-252 — provider edit modal. SecureField for API key OR TextField
// for host URL depending on the provider's credential kind. Save persists
// the credential; Test runs a probe and surfaces the toast; Delete wipes
// the row. The sheet stays open after Save so the user can immediately
// hit Test on the freshly-stored key.

import LuminaVaultShared
import SwiftUI

struct ProviderEditSheet: View {
    let provider: ProviderID
    let existing: ProviderCredentialDTO?
    let onSave: (ProviderCredentialKind, String?, String?, String?) async -> Bool
    let onTest: () async -> ProvidersPaneViewModel.TestResult?
    let onDelete: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var baseUrl: String = ""
    @State private var label: String = ""
    @State private var isSaving = false
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch credentialKind {
                    case .apiKey, .oauth:
                        SecureField("API key", text: $apiKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Base URL (optional)", text: $baseUrl)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    case .hostURL:
                        TextField("Host URL", text: $baseUrl)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    TextField("Label (optional)", text: $label)
                } header: {
                    Text(ProvidersPaneViewModel.displayName(for: provider))
                } footer: {
                    Text(footer)
                        .font(LVTypography.footnote.font)
                        .foregroundStyle(.secondary)
                }

                if existing?.hasCredential == true {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                await onDelete()
                                dismiss()
                            }
                        } label: {
                            Text("Remove credential")
                        }
                    }
                }
            }
            .navigationTitle("Edit provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button(action: save) {
                            Label("Save", systemImage: "tray.and.arrow.down")
                        }
                        .disabled(isSaving || !canSave)
                        Button(action: test) {
                            Label("Test connection", systemImage: "bolt.horizontal")
                        }
                        .disabled(isTesting || existing?.hasCredential != true && !canSave)
                    } label: {
                        if isSaving || isTesting {
                            ProgressView()
                        } else {
                            Text("Done")
                        }
                    }
                }
            }
            .onAppear {
                baseUrl = existing?.baseUrl ?? ""
                label = existing?.label ?? ""
            }
        }
    }

    private var credentialKind: ProviderCredentialKind {
        existing?.kind ?? ProvidersPaneViewModel.defaultKind(for: provider)
    }

    private var canSave: Bool {
        switch credentialKind {
        case .apiKey, .oauth: !apiKey.isEmpty
        case .hostURL: !baseUrl.isEmpty
        }
    }

    private var footer: String {
        switch provider {
        case .xai: "Get a key at https://x.ai. Stored encrypted at rest."
        case .nvidia: "Get a key at https://build.nvidia.com (prefix nvapi-). Stored encrypted at rest."
        case .anthropic: "Get a key at https://console.anthropic.com."
        case .openai: "Get a key at https://platform.openai.com/api-keys."
        case .openRouter: "Get a key at https://openrouter.ai/keys. Works as a fallback chain entry."
        case .ollama: "Host URL of your self-hosted Ollama (e.g. http://192.168.1.42:11434 or a Tailscale name)."
        }
    }

    private func save() {
        Task {
            isSaving = true
            let ok = await onSave(credentialKind, apiKey.isEmpty ? nil : apiKey, baseUrl.isEmpty ? nil : baseUrl, label.isEmpty ? nil : label)
            isSaving = false
            if ok { apiKey = "" }
        }
    }

    private func test() {
        Task {
            isTesting = true
            _ = await onTest()
            isTesting = false
        }
    }
}
