// LuminaVaultClient/LuminaVaultClient/Features/Settings/LLMPreferences/LLMPreferencesPaneView.swift
//
// HER-252 — Settings → Intelligence pane (formerly "Model Preferences").
// Picks the user's primary (provider, model) and an ordered fallback
// chain.
//
// HER-300 ticket 5 — the pane now surfaces the active LLM brain
// (managed vs BYOK) at the top, exposes a segmented picker to switch
// modes, and renders the primary + fallback editor in a disabled,
// muted state when on Managed (so users can preview what their BYOK
// config would look like without accidentally editing it). On BYOK we
// add a "Manage API Keys →" entry that pushes the existing
// `ProvidersPaneView`. Save persists the chosen `mode`; managed mode
// always pins the canonical OpenRouter/Qwen pair on the wire.

import LuminaVaultShared
import SwiftUI

struct LLMPreferencesPaneView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(AppState.self) private var appState
    @State private var viewModel: LLMPreferencesPaneViewModel

    /// HER-300 — used to push the live BYOK key manager from the BYOK
    /// branch. Injected so this pane doesn't reach into `AppState` for
    /// its own factory.
    private let providersClient: ProvidersClientProtocol

    init(
        client: LLMPreferencesClientProtocol,
        providersClient: ProvidersClientProtocol
    ) {
        _viewModel = State(initialValue: LLMPreferencesPaneViewModel(client: client, providersClient: providersClient))
        self.providersClient = providersClient
    }

    var body: some View {
        Form {
            currentlyPoweringSection

            modePickerSection

            primaryEditorSection
            fallbackEditorSection

            if viewModel.mode == .byok {
                routingBlockedSection
                routingAllowSection
                manageKeysSection
            }

            saveSection

            if case let .failed(message) = viewModel.state {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        // Clear the app-wide floating LVTabBar so the Save section isn't
        // hidden under it (matches SettingsRootView's bottom clearance).
        .contentMargins(.bottom, LVSpacing.hero + LVSpacing.xxl, for: .scrollContent)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    // MARK: - Sections

    /// HER-300 — "Currently powering you" card. Surfaces the live brain
    /// so the user knows what's actually serving their requests; the
    /// managed copy spells out that LuminaVault foots the bill.
    private var currentlyPoweringSection: some View {
        Section {
            HStack(alignment: .top, spacing: LVSpacing.base) {
                LVIconView(.brainPremium, size: 28, tint: palette.accent, weight: .medium)
                    .frame(width: LVSize.rowGlyph)

                VStack(alignment: .leading, spacing: LVSpacing.xs) {
                    Text("Currently powering you")
                        .lvFont(.microTag)
                        .tracking(1.5)
                        .foregroundStyle(palette.textSecondary)
                    Text(currentlyPoweringTitle)
                        .lvFont(.bodyEmphasis)
                        .foregroundStyle(palette.textPrimary)
                    Text(currentlyPoweringSubtitle)
                        .lvFont(.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, LVSpacing.xs)
        }
    }

    private var currentlyPoweringTitle: String {
        switch viewModel.mode {
        case .managed:
            return "Qwen2.5-72B"
        case .byok:
            if viewModel.primaryModel.isEmpty {
                return ProvidersPaneViewModel.displayName(for: viewModel.primaryProvider)
            }
            return viewModel.primaryModel
        }
    }

    private var currentlyPoweringSubtitle: String {
        switch viewModel.mode {
        case .managed:
            return "Managed by LuminaVault · no API key needed"
        case .byok:
            return "Your \(ProvidersPaneViewModel.displayName(for: viewModel.primaryProvider)) key"
        }
    }

    /// HER-300 — segmented mode picker. Segmented (vs menu) so both
    /// options are visible at a glance; this is the single most
    /// important toggle on the screen and shouldn't be hidden behind
    /// a tap.
    private var modePickerSection: some View {
        Section {
            Picker("Brain", selection: Binding(
                get: { viewModel.mode },
                set: { newValue in
                    viewModel.mode = newValue
                    viewModel.markDirty()
                },
            )) {
                Text("Managed").tag(LLMBrainMode.managed)
                Text("My API Keys").tag(LLMBrainMode.byok)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Brain")
        } footer: {
            Text(modePickerFooter)
                .font(.footnote)
        }
    }

    private var modePickerFooter: String {
        switch viewModel.mode {
        case .managed:
            return "LuminaVault funds Qwen2.5-72B for every chat, query, and kb-compile call."
        case .byok:
            return "Routes traffic through your own provider keys. Manage them below."
        }
    }

    private var isEditorDisabled: Bool { viewModel.mode == .managed }

    private var keyFieldPlaceholder: String {
        let name = ProvidersPaneViewModel.displayName(for: viewModel.primaryProvider)
        if ProvidersPaneViewModel.defaultKind(for: viewModel.primaryProvider) == .hostURL {
            return "\(name) host URL (e.g. http://…:11434)"
        }
        if viewModel.primaryProvider == .xai {
            return "Grok (xAI) API key (leave blank to use linked SuperGrok)"
        }
        return "\(name) API key"
    }

    private var primaryEditorSection: some View {
        Section {
            Picker("Provider", selection: Binding(
                get: { viewModel.primaryProvider },
                set: { viewModel.selectProvider($0) },
            )) {
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    Text(ProvidersPaneViewModel.displayName(for: provider)).tag(provider)
                }
            }
            // BYOK v2 — model is a Picker from the curated catalog (no typos).
            // Providers without a catalog (ollama) keep a free-text field.
            if viewModel.usesModelCatalog {
                Picker("Model", selection: Binding(
                    get: { viewModel.pickerSelectedModel },
                    set: { newValue in
                        viewModel.primaryModel = newValue
                        viewModel.markDirty()
                    },
                )) {
                    ForEach(viewModel.modelPickerOptions) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
            } else {
                TextField("Model", text: Binding(
                    get: { viewModel.primaryModel },
                    set: { newValue in
                        viewModel.primaryModel = newValue
                        viewModel.markDirty()
                    },
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
            // BYOK v2 — API key on the same screen as provider + model.
            if !isEditorDisabled {
                SecureField(
                    keyFieldPlaceholder,
                    text: Binding(
                        get: { viewModel.apiKeyInput },
                        set: { newValue in
                            viewModel.apiKeyInput = newValue
                            viewModel.markDirty()
                        },
                    ),
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
        } header: {
            Text("Primary")
        } footer: {
            if isEditorDisabled {
                Text("Switch to **My API Keys** to edit your primary provider.")
                    .font(.footnote)
            } else {
                if viewModel.primaryProvider == .xai {
                    Text("For Grok (xAI): leave blank to use linked SuperGrok account (after Connect in Linked Accounts). Enter key to override with a developer API key.")
                        .font(.footnote)
                } else {
                    Text("Tried first on every chat. Leave the key blank to keep the one already saved; enter a new key to replace it. Stored encrypted.")
                        .font(.footnote)
                }
            }
        }
        .disabled(isEditorDisabled)
        .opacity(isEditorDisabled ? 0.5 : 1.0)
    }

    private var fallbackEditorSection: some View {
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
            if isEditorDisabled {
                Text("Available when **My API Keys** is selected.")
                    .font(.footnote)
            } else {
                Text("Walked in order when the primary returns credit-exhausted, rate-limit, or upstream-error.")
                    .font(.footnote)
            }
        }
        .disabled(isEditorDisabled)
        .opacity(isEditorDisabled ? 0.5 : 1.0)
    }

    private var routingBlockedSection: some View {
        Section {
            ForEach(ProviderID.allCases, id: \.self) { provider in
                Toggle(isOn: Binding(
                    get: { viewModel.blockedProviders.contains(provider) },
                    set: { _ in viewModel.toggleBlocked(provider) }
                )) {
                    Text(ProvidersPaneViewModel.displayName(for: provider))
                }
            }
        } header: {
            Text("Blocked providers")
        } footer: {
            Text("The router never routes to a blocked provider.")
                .font(.footnote)
        }
    }

    private var routingAllowSection: some View {
        Section {
            ForEach(ProviderID.allCases, id: \.self) { provider in
                Toggle(isOn: Binding(
                    get: { viewModel.allowedProviders.contains(provider) },
                    set: { _ in viewModel.toggleAllowed(provider) }
                )) {
                    Text(ProvidersPaneViewModel.displayName(for: provider))
                }
                .disabled(viewModel.blockedProviders.contains(provider))
            }
        } header: {
            Text("Restrict to (allow-list)")
        } footer: {
            Text("Leave all off to allow every provider. When any are on, only those are used.")
                .font(.footnote)
        }
    }

    private var manageKeysSection: some View {
        Section {
            NavigationLink {
                ProvidersPaneView(client: providersClient)
            } label: {
                HStack {
                    Label("Manage API Keys", systemImage: "key.fill")
                    Spacer()
                }
            }
        } footer: {
            Text("Add, rotate, or remove the API keys your BYOK chain uses.")
                .font(.footnote)
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                Task {
                    await viewModel.save()
                    // BYOK v2 — on a successful save, signal ChatView to start a
                    // fresh conversation on the new config.
                    if case .failed = viewModel.state {} else {
                        appState.llmConfigVersion += 1
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Save")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(!viewModel.canSave)
        }
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
