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

    /// For xAI we support two modes: normal apiKey or oauth marker (linked SuperGrok).
    /// When .linked we save kind=.oauth with no key.
    private enum XaiAuthChoice { case apiKey, linked }
    @State private var xaiChoice: XaiAuthChoice = .apiKey

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if provider == .xai {
                        Picker("Authentication", selection: $xaiChoice) {
                            Text("API key").tag(XaiAuthChoice.apiKey)
                            Text("Linked xAI account (SuperGrok)").tag(XaiAuthChoice.linked)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: xaiChoice) { _, newValue in
                            if newValue == .linked {
                                apiKey = ""
                                baseUrl = ""
                            }
                        }
                    }

                    if provider == .xai && xaiChoice == .linked {
                        Text("Using your connected SuperGrok subscription via the secure container link. No separate API key is required or stored.")
                            .font(LVTypography.footnote.font)
                            .foregroundStyle(.secondary)
                    } else {
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
                    }
                    if provider != .xai || xaiChoice != .linked {
                        TextField("Label (optional)", text: $label)
                    }
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
                        .disabled(isTesting || (existing?.hasCredential != true && !canSave))
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
                if provider == .xai, existing?.kind == .oauth {
                    xaiChoice = .linked
                } else if provider == .xai {
                    xaiChoice = .apiKey
                }
            }
        }
    }

    private var credentialKind: ProviderCredentialKind {
        existing?.kind ?? ProvidersPaneViewModel.defaultKind(for: provider)
    }

    private var canSave: Bool {
        let effectiveKind = (provider == .xai && xaiChoice == .linked) ? ProviderCredentialKind.oauth : credentialKind
        return switch effectiveKind {
        case .oauth: true // marker row from linked account
        case .apiKey: !apiKey.isEmpty
        case .hostURL: !baseUrl.isEmpty
        }
    }

    private var footer: String {
        switch provider {
        case .xai: "API key from https://x.ai, or connect your SuperGrok account in Linked Accounts to use without a separate key."
        case .nvidia: "Get a key at https://build.nvidia.com (prefix nvapi-). Stored encrypted at rest."
        case .gemini: "Get a key at https://aistudio.google.com/apikey. Free tier handles large prompts. Stored encrypted at rest."
        case .anthropic: "Get a key at https://console.anthropic.com."
        case .openai: "Get a key at https://platform.openai.com/api-keys."
        case .openRouter: "Get a key at https://openrouter.ai/keys. Works as a fallback chain entry."
        case .ollama: "Host URL of your self-hosted Ollama (e.g. http://192.168.1.42:11434 or a Tailscale name)."
        case .nous: "Get a key at https://portal.nousresearch.com. Includes rotating free models (e.g. stepfun/step-3.7-flash:free). Stored encrypted at rest."
        }
    }

    private func save() {
        Task {
            isSaving = true
            let kindToSend: ProviderCredentialKind = (provider == .xai && xaiChoice == .linked) ? .oauth : credentialKind
            let keyToSend: String? = (kindToSend == .oauth) ? nil : (apiKey.isEmpty ? nil : apiKey)
            let urlToSend: String? = (kindToSend == .oauth && provider == .xai) ? nil : (baseUrl.isEmpty ? nil : baseUrl)
            let ok = await onSave(kindToSend, keyToSend, urlToSend, label.isEmpty ? nil : label)
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
