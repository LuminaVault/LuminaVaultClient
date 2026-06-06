// LuminaVaultClient/LuminaVaultClient/Features/Settings/HermesGatewayPaneView.swift
//
// HER-218 — Settings → Connections → Hermes Server pane.
// "Bring Your Own Hermes": Managed default vs connect-your-own self-hosted
// instance. Auth supports none / Bearer token / username & password (Basic).

import SwiftUI

struct HermesGatewayPaneView: View {
    @State private var viewModel: HermesGatewayViewModel
    @State private var showDisconnectConfirm = false

    init(client: any SettingsClientProtocol) {
        _viewModel = State(initialValue: HermesGatewayViewModel(client: client))
    }

    var body: some View {
        List {
            switch viewModel.state {
            case .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .empty:
                emptyStateSection
            case let .configured(baseUrl, hasAuthHeader, status):
                configuredSection(baseUrl: baseUrl, hasAuthHeader: hasAuthHeader, status: status)
            case let .editing(prefilledBaseUrl, prefilledHasAuthHeader):
                editingSection(prefilledBaseUrl: prefilledBaseUrl, prefilledHasAuthHeader: prefilledHasAuthHeader)
            }

            if let error = viewModel.lastError {
                Section { Text(error).foregroundStyle(.red) }
            }
            if let verifyError = viewModel.verifyError {
                Section {
                    Text(verifyError.displayMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Hermes Server")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Sections

    private var emptyStateSection: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Currently using **LuminaVault managed Hermes** — nothing to set up.")
                        .font(.body)
                    Button("Connect my own Hermes →") { viewModel.useMyOwnGateway() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Your brain server")
            } footer: {
                Text("Point LuminaVault at a self-hosted Hermes instance (e.g. on your own VPS) instead of the managed default.")
            }

            connectivityGuidanceSection
        }
    }

    /// How to make a self-hosted Hermes reachable. Surfaced in both the empty
    /// and editing states. Key point: the LuminaVault **server** (not your
    /// phone) connects to your Hermes, so it must be reachable from the public
    /// internet over https://.
    private var connectivityGuidanceSection: some View {
        Section {
            DisclosureGroup("How do I expose my Hermes?") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("LuminaVault's server connects to your Hermes on your behalf, so it must be reachable from the **public internet**. Local/LAN, localhost and private IPs are always rejected.")
                    Divider()
                    Text("**Public HTTPS URL** (recommended)")
                        .font(.subheadline.weight(.semibold))
                    Text("Put Hermes behind TLS on a domain you control, e.g. `https://hermes.yourdomain.com` (Caddy/Nginx/Traefik reverse proxy).")
                    Divider()
                    Text("**Cloudflare Tunnel**")
                        .font(.subheadline.weight(.semibold))
                    Text("No port-forwarding and works behind CGNAT. Run `cloudflared tunnel` on the VPS and paste the resulting `https://…` hostname.")
                    Divider()
                    Text("**Public IP / http:// (advanced)**")
                        .font(.subheadline.weight(.semibold))
                    Text("A bare public IP or plain `http://` is allowed but insecure — the auth token is sent in plaintext and the connection can't be verified. Only use on a trusted network.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func configuredSection(
        baseUrl: String,
        hasAuthHeader: Bool,
        status: HermesGatewayViewModel.VerifyStatus,
    ) -> some View {
        Section("Connected Hermes") {
            LabeledContent("Base URL", value: baseUrl)
            LabeledContent("Authentication", value: hasAuthHeader ? "Set" : "None")
            switch status {
            case .unverified:
                LabeledContent("Status", value: "Not verified")
                    .foregroundStyle(.secondary)
            case .verified(let at):
                LabeledContent("Verified", value: at.formatted(.relative(presentation: .named)))
                    .foregroundStyle(.green)
            }
        }
        Section {
            Button("Test again") { Task { await viewModel.testAgain() } }
                .disabled(viewModel.isWorking)
            Button("Update credentials") { viewModel.editExistingConfig() }
                .disabled(viewModel.isWorking)
            Button("Disconnect", role: .destructive) { showDisconnectConfirm = true }
                .disabled(viewModel.isWorking)
        }
        .confirmationDialog(
            "Stop using your own Hermes?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible,
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await viewModel.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("LuminaVault will go back to the managed Hermes. Your existing memories and vault are untouched.")
        }
    }

    @ViewBuilder
    private func editingSection(prefilledBaseUrl: String?, prefilledHasAuthHeader: Bool) -> some View {
        Section {
            TextField("My VPS (optional)", text: $viewModel.nameInput)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        } header: {
            Text("Name")
        } footer: {
            Text("A friendly label for this Hermes. Optional.")
        }

        Section {
            TextField("https://hermes.example.com", text: $viewModel.baseUrlInput)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Hermes URL")
        } footer: {
            Text("Must be reachable from the public internet. https:// with a domain is strongly recommended; http:// and raw IPs are allowed but insecure (see warning below). Private/LAN addresses are rejected.")
        }

        if let warning = viewModel.transportWarning {
            Section {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }

        Section {
            Picker("Authentication", selection: $viewModel.authMode) {
                ForEach(HermesGatewayViewModel.AuthMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            switch viewModel.authMode {
            case .none:
                EmptyView()
            case .bearer:
                SecureField(
                    prefilledHasAuthHeader ? "Replace token" : "Token (e.g. abc123)",
                    text: $viewModel.authHeaderInput,
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            case .basic:
                TextField("Username", text: $viewModel.basicUsernameInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $viewModel.basicPasswordInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Authentication")
        } footer: {
            Text(authFooter(prefilledHasAuthHeader: prefilledHasAuthHeader))
        }

        connectivityGuidanceSection

        Section {
            Button("Save & verify") { Task { await viewModel.submit() } }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking || viewModel.baseUrlInput.isEmpty)
            Button("Cancel") { Task { await viewModel.cancelEditing() } }
                .disabled(viewModel.isWorking)
        }
    }

    private func authFooter(prefilledHasAuthHeader: Bool) -> String {
        switch viewModel.authMode {
        case .none:
            return "Choose this if your Hermes is open / unauthenticated."
        case .bearer:
            let rotate = prefilledHasAuthHeader ? " Leave blank to keep the existing token." : ""
            return "Sent as an Authorization: Bearer header.\(rotate) Credentials are never returned in plaintext after save."
        case .basic:
            return "For a password-protected Hermes (HTTP Basic auth). Combined into an Authorization header. Use https:// so the credentials aren't sent in plaintext."
        }
    }
}
