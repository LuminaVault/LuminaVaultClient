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
// `ProvidersPaneView`. Save persists the chosen `mode`; the backend owns
// and returns the effective managed provider/model.

import LuminaVaultShared
import SwiftUI

struct LLMPreferencesPaneView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(AppState.self) private var appState
    @State private var viewModel: LLMPreferencesPaneViewModel
    @State private var hybridSettings = HybridExecutionSettingsStore()

    /// HER-300 — used to push the live BYOK key manager from the BYOK
    /// branch. Injected so this pane doesn't reach into `AppState` for
    /// its own factory.
    private let providersClient: ProvidersClientProtocol
    private let hybridClient: (any ChatExperienceClientProtocol)?

    init(
        client: LLMPreferencesClientProtocol,
        providersClient: ProvidersClientProtocol,
        routerClient: RouterClientProtocol? = nil,
        hybridClient: (any ChatExperienceClientProtocol)? = nil
    ) {
        _viewModel = State(initialValue: LLMPreferencesPaneViewModel(
            client: client,
            providersClient: providersClient,
            routerClient: routerClient
        ))
        self.providersClient = providersClient
        self.hybridClient = hybridClient
    }

    var body: some View {
        Form {
            currentlyPoweringSection

            routingPolicySection
            routerProfileSection
            routerAnalyticsSection
            routerObjectiveSection
            routerBudgetSection

            modePickerSection
            hybridExecutionSection

            primaryEditorSection
            fallbackEditorSection

            if viewModel.mode == .byok {
                byokKeysCalloutSection
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
        .navigationTitle("Model Router")
        .navigationBarTitleDisplayMode(.inline)
        // Clear the app-wide floating LVTabBar so the Save section isn't
        // hidden under it (matches SettingsRootView's bottom clearance).
        .contentMargins(.bottom, LVSpacing.hero + LVSpacing.xxl, for: .scrollContent)
        .task {
            await viewModel.load()
            if let hybridClient {
                await hybridSettings.loadCrossDevicePreferences(using: hybridClient)
            }
        }
        .refreshable { await viewModel.load() }
    }

    // MARK: - Sections

    private var hybridExecutionSection: some View {
        Section {
            Toggle("Use Apple on-device model", isOn: $hybridSettings.useAppleOnDeviceModel)
            if hybridSettings.useAppleOnDeviceModel {
                Text("Uses Apple Intelligence entirely on device when available on iOS 26.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Picker("Execution profile", selection: $hybridSettings.profile) {
                Text("Private").tag(HybridExecutionProfile.private)
                Text("Balanced").tag(HybridExecutionProfile.balanced)
                Text("Quality").tag(HybridExecutionProfile.quality)
            }
            Toggle("Allow local fallback", isOn: $hybridSettings.localFallbackEnabled)
                .disabled(hybridSettings.profile != .quality)
            Toggle("Allow cloud fallback", isOn: $hybridSettings.cloudFallbackEnabled)
                .disabled(hybridSettings.profile != .balanced)
            Toggle("Sync local conversations", isOn: $hybridSettings.syncLocalConversations)
                .disabled(hybridSettings.profile == .private)
            Picker("Local server", selection: $hybridSettings.endpointKind) {
                Text("Ollama").tag(LocalEndpointKind.ollama)
                Text("LM Studio").tag(LocalEndpointKind.lmStudio)
                Text("MLX server").tag(LocalEndpointKind.mlxServer)
                Text("OpenAI-compatible").tag(LocalEndpointKind.openAICompatible)
            }
            .disabled(hybridSettings.useAppleOnDeviceModel)
            TextField("Endpoint URL", text: $hybridSettings.endpointURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(hybridSettings.useAppleOnDeviceModel)
            TextField("Local model", text: $hybridSettings.model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(hybridSettings.useAppleOnDeviceModel)
            SecureField("Local endpoint API key (optional)", text: $hybridSettings.apiKey)
                .disabled(hybridSettings.useAppleOnDeviceModel)
            Button(hybridSettings.isTestingConnection ? "Testing local model…" : "Test local model") {
                Task { await hybridSettings.testConnection() }
            }
            .disabled(hybridSettings.isTestingConnection || (!hybridSettings.useAppleOnDeviceModel && hybridSettings.configuration == nil))
            if let status = hybridSettings.connectionStatus {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Local model status: \(status)")
            }
            Button("Save local execution settings") {
                hybridSettings.save()
                if let hybridClient {
                    Task { await hybridSettings.saveCrossDevicePreferences(using: hybridClient) }
                }
            }
            .disabled(!hybridSettings.useAppleOnDeviceModel && hybridSettings.configuration == nil)
        } header: {
            Text("Hybrid execution")
        } footer: {
            Text("Private never sends prompts to LuminaVault. Balanced prefers local and can fall back to cloud. Quality prefers cloud and can fall back locally. Disable conversation sync to keep locally generated turns only on this device.")
        }
    }

    private var routingPolicySection: some View {
        Section {
            Picker("Policy", selection: Binding(
                get: { viewModel.routingPolicy },
                set: { viewModel.selectRoutingPolicy($0) }
            )) {
                ForEach(LLMRoutingPolicy.allCases, id: \.self) { policy in
                    // Auto (Smart) is the server default — flag it so users
                    // who wandered in here know which one to pick.
                    Text(policy == .autoSmart
                        ? "\(policy.displayName) — Recommended"
                        : policy.displayName)
                        .tag(policy)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Auto model selection")
        } footer: {
            Text(routingPolicyFooter)
        }
    }

    private var routingPolicyFooter: String {
        switch viewModel.routingPolicy {
        case .autoSmart:
            return "Picks the smallest model that can handle each turn using your keys (or managed models). Complex work escalates automatically."
        case .fastCheap:
            return "Bias toward speed and cost. Best for light chat when quality risk is acceptable."
        case .balanced:
            return "Even mix of quality, cost, and latency — a good daily driver."
        case .maxQuality:
            return "Prefer frontier models. Still uses a fast model on clearly trivial turns."
        case .locked:
            return "Always use your primary model. Disable Auto routing."
        }
    }

    private var byokKeysCalloutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                Text("Bring your own keys")
                    .font(.headline)
                Text("Auto (Smart) only routes across models you have keys for. OpenRouter is recommended — one key unlocks cheap and frontier models.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Without a key, chat is blocked until you add one or switch to Managed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, LVSpacing.xs)
        }
    }

    @ViewBuilder
    private var routerProfileSection: some View {
        if !viewModel.routerProfiles.isEmpty {
            Section {
                Picker("Active profile", selection: Binding(
                    get: { viewModel.selectedRouterProfileID },
                    set: { id in
                        guard let id else { return }
                        viewModel.selectRouterProfile(id)
                    }
                )) {
                    ForEach(viewModel.routerProfiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
            } header: {
                Text("Routing profile")
            } footer: {
                Text("Jobs override Spaces, and Spaces override this default profile.")
            }
        }
    }

    @ViewBuilder
    private var routerAnalyticsSection: some View {
        if let dashboard = viewModel.routerDashboard {
            Section("This month") {
                LabeledContent("Requests", value: dashboard.requests.formatted())
                LabeledContent("Tokens", value: (dashboard.tokensIn + dashboard.tokensOut).formatted())
                LabeledContent(
                    "Estimated cost",
                    value: (Double(dashboard.estimatedCostUsdMicros) / 1_000_000)
                        .formatted(.currency(code: "USD"))
                )
                LabeledContent("Average latency", value: "\(dashboard.averageLatencyMs) ms")
            }
        }
    }

    @ViewBuilder
    private var routerObjectiveSection: some View {
        if viewModel.selectedRouterProfile != nil {
            Section {
                VStack(alignment: .leading) {
                    LabeledContent("Quality", value: "\(Int(viewModel.qualityWeight))%")
                    Slider(
                        value: Binding(
                            get: { viewModel.qualityWeight },
                            set: { viewModel.updateQualityWeight($0) }
                        ),
                        in: 0 ... 100,
                        step: 5
                    )
                    .accessibilityLabel("Quality routing weight")
                }
                VStack(alignment: .leading) {
                    LabeledContent("Cost", value: "\(Int(viewModel.costWeight))%")
                    Slider(
                        value: Binding(
                            get: { viewModel.costWeight },
                            set: { viewModel.updateCostWeight($0) }
                        ),
                        in: 0 ... Double(max(0, 100 - Int(viewModel.qualityWeight))),
                        step: 5
                    )
                    .accessibilityLabel("Cost routing weight")
                }
                LabeledContent("Latency", value: "\(viewModel.latencyWeight)%")
            } header: {
                Text("Routing objective")
            } footer: {
                Text("Cerberus combines task quality, predicted cost, and observed latency. The weights always total 100%.")
            }
        }
    }

    @ViewBuilder
    private var routerBudgetSection: some View {
        if viewModel.selectedRouterProfile != nil {
            Section {
                TextField("Soft limit", value: $viewModel.softBudgetUSD, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                TextField("Hard limit", value: $viewModel.hardBudgetUSD, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
            } header: {
                Text("Monthly budget")
            } footer: {
                Text("At the soft limit Cerberus favors cheaper routes. The hard limit blocks additional priced calls. Use 0 for no limit.")
            }
            .onChange(of: viewModel.softBudgetUSD) { _, _ in viewModel.routerDirty = true }
            .onChange(of: viewModel.hardBudgetUSD) { _, _ in viewModel.routerDirty = true }
        }
    }

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
        if viewModel.primaryModel.isEmpty {
            return ProvidersPaneViewModel.displayName(for: viewModel.primaryProvider)
        }
        return viewModel.modelPickerOptions
            .first(where: { $0.id == viewModel.primaryModel })?
            .displayName ?? viewModel.primaryModel
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
                }
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
            return "LuminaVault funds the server-selected model for chat, query, and knowledge compilation."
        case .byok:
            return "Routes traffic through your own provider keys. Manage them below."
        }
    }

    private var isEditorDisabled: Bool {
        viewModel.mode == .managed
    }

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
                set: { viewModel.selectProvider($0) }
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
                    }
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
                    }
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
                        }
                    )
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
                    set: { viewModel.updateFallback(at: index, provider: $0) }
                )) {
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        Text(ProvidersPaneViewModel.displayName(for: provider)).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)

                TextField("Model", text: Binding(
                    get: { step.model },
                    set: { viewModel.updateFallback(at: index, model: $0) }
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
