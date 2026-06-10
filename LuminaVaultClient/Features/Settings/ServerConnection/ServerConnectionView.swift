// LuminaVaultClient/LuminaVaultClient/Features/Settings/ServerConnection/ServerConnectionView.swift
//
// HER-250 — Settings → Server Connection. Backend mode picker + SOUL.md
// editor. Both `.byo` (self-hosted LuminaVault server) and `.tailscale`
// (tailnet host) take a user-entered URL, health-probe it, persist it
// (BYOServerStore / TailscaleServerStore), and switch mode — which forces a
// clean re-login against the new server. Tailscale host entry is manual
// (iOS doesn't expose tailnet state to apps).

import LuminaVaultShared
import SwiftUI

// HER-262 — `BackendMode` is now defined in `Services/ServerConnection/
// BackendMode.swift` so `Config.apiBaseURL` can read it. This view model
// delegates persistence + change-notification to `BackendModeStore`.

@Observable
@MainActor
final class ServerConnectionViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }
    var state: LoadState = .loading
    var soulBody: String = ""
    var soulSaving: Bool = false
    var mode: BackendMode
    // BYO LuminaVault server (self-hosted) editor state.
    var byoURLInput: String = ""
    var byoTesting: Bool = false
    var byoError: String?
    // Tailscale tailnet-host editor state.
    var tailscaleURLInput: String = ""
    var tailscaleTesting: Bool = false
    var tailscaleError: String?
    private let soulClient: SoulClientProtocol
    private let healthClient: HealthClientProtocol

    init(soulClient: SoulClientProtocol, healthClient: HealthClientProtocol = HealthHTTPClient()) {
        self.soulClient = soulClient
        self.healthClient = healthClient
        self.mode = BackendModeStore.current
        self.byoURLInput = BYOServerStore.url?.absoluteString ?? ""
        self.tailscaleURLInput = TailscaleServerStore.url?.absoluteString ?? ""
    }

    /// Caution banner when the typed BYO URL trades away transport security.
    var byoTransportWarning: String? {
        URLValidation.transportWarning(for: byoURLInput)
    }

    /// Tailscale runs over WireGuard, so `http://` to a tailnet host is fine —
    /// suppress the plaintext/bare-IP cautions that apply to public URLs.
    var tailscaleTransportWarning: String? {
        URLValidation.transportWarning(for: tailscaleURLInput, assumeSecureTunnel: true)
    }

    /// Validates + health-probes the typed URL, then persists it and switches
    /// to `.byo`. Switching backend mode posts `modeChangedNotification`,
    /// which the app root observes to force a clean re-login against the new
    /// server (the existing session token belongs to the old endpoint).
    func testAndSave() async {
        let trimmed = byoURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URLValidation.isValidBaseURL(trimmed), let url = URL(string: trimmed) else {
            byoError = "Enter a valid http:// or https:// URL with a host."
            return
        }
        byoError = nil
        byoTesting = true
        defer { byoTesting = false }
        let ok = await healthClient.isReachable(baseURL: url)
        guard ok else {
            byoError = "Couldn't reach \(url.host ?? trimmed)/health. "
                + "Check the URL and that your server is running."
            return
        }
        BYOServerStore.set(trimmed)
        setMode(.byo)
    }

    /// Tailnet equivalent of `testAndSave`: validate + health-probe the typed
    /// tailnet host, persist it, then switch to `.tailscale` (which forces a
    /// clean re-login against the new server via `modeChangedNotification`).
    func testAndSaveTailscale() async {
        let trimmed = tailscaleURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URLValidation.isValidBaseURL(trimmed), let url = URL(string: trimmed) else {
            tailscaleError = "Enter a valid http:// or https:// URL with a host."
            return
        }
        tailscaleError = nil
        tailscaleTesting = true
        defer { tailscaleTesting = false }
        let ok = await healthClient.isReachable(baseURL: url)
        guard ok else {
            tailscaleError = "Couldn't reach \(url.host ?? trimmed)/health. "
                + "Check the host and that you're connected to the tailnet."
            return
        }
        TailscaleServerStore.set(trimmed)
        setMode(.tailscale)
    }

    func load() async {
        state = .loading
        do {
            let response = try await soulClient.get()
            soulBody = response.markdown
            state = .loaded
        } catch {
            state = .failed("Couldn't load SOUL.md.")
        }
    }

    func setMode(_ newMode: BackendMode) {
        mode = newMode
        BackendModeStore.set(newMode)
    }

    func saveSoul() async {
        soulSaving = true
        defer { soulSaving = false }
        do {
            let response = try await soulClient.put(SoulPutRequest(markdown: soulBody))
            soulBody = response.markdown
        } catch {
            state = .failed("Couldn't save SOUL.md.")
        }
    }
}

struct ServerConnectionView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: ServerConnectionViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: LVSpacing.lg) {
                    modeSection
                    soulSection
                    debugSection
                }
                .padding(.horizontal, LVSpacing.lg)
                .padding(.vertical, LVSpacing.xl)
            }
        }
        .navigationTitle("Server Connection")
        .lvBackground()
        .task { await vm.load() }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            sectionLabel("Backend mode")
            VStack(spacing: LVSpacing.sm) {
                ForEach(BackendMode.allCases) { mode in
                    Button {
                        vm.setMode(mode)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: LVSpacing.hairline) {
                                Text(mode.label)
                                    .font(LVTypography.fieldLabel.font)
                                    .foregroundStyle(palette.textPrimary)
                                Text(mode.subtitle)
                                    .font(LVTypography.caption.font)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            if vm.mode == mode {
                                LVIconView(.checkmarkCircleFill, tint: palette.primary)
                            }
                        }
                        .padding(LVSpacing.md)
                        .background(palette.backgroundBase.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: LVRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: LVRadius.md)
                                .stroke(vm.mode == mode ? palette.primary : palette.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            if vm.mode == .byo {
                byoEditor
            }
            if vm.mode == .tailscale {
                tailscaleEditor
            }
        }
    }

    private var byoEditor: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text("Self-hosted server URL")
                .font(LVTypography.fieldLabel.font)
                .foregroundStyle(palette.textPrimary)
            TextField("https://vault.example.com", text: $vm.byoURLInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(LVTypography.mono.font)
                .padding(LVSpacing.sm)
                .background(palette.backgroundBase.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: LVRadius.md))
            if let warning = vm.byoTransportWarning {
                Text(warning)
                    .font(LVTypography.caption.font)
                    .foregroundStyle(.orange)
            }
            if let error = vm.byoError {
                Text(error)
                    .font(LVTypography.caption.font)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Test & Save") { Task { await vm.testAndSave() } }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.primary)
                    .disabled(vm.byoTesting || vm.byoURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Saving signs you out so you can log in against your server.")
                .font(LVTypography.caption.font)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(LVSpacing.md)
        .background(palette.backgroundBase.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: LVRadius.md))
    }

    private var tailscaleEditor: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text("Tailnet host")
                .font(LVTypography.fieldLabel.font)
                .foregroundStyle(palette.textPrimary)
            TextField("http://vault.tailnet-name.ts.net:8080", text: $vm.tailscaleURLInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(LVTypography.mono.font)
                .padding(LVSpacing.sm)
                .background(palette.backgroundBase.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: LVRadius.md))
            if let warning = vm.tailscaleTransportWarning {
                Text(warning)
                    .font(LVTypography.caption.font)
                    .foregroundStyle(.orange)
            }
            if let error = vm.tailscaleError {
                Text(error)
                    .font(LVTypography.caption.font)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Test & Save") { Task { await vm.testAndSaveTailscale() } }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.primary)
                    .disabled(vm.tailscaleTesting || vm.tailscaleURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Enter the MagicDNS name or tailnet IP of your LuminaVault server. "
                + "Tailscale (WireGuard) encrypts the connection, so plain http:// is fine here. "
                + "Saving signs you out so you can log in against that server.")
                .font(LVTypography.caption.font)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(LVSpacing.md)
        .background(palette.backgroundBase.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: LVRadius.md))
    }

    private var soulSection: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            sectionLabel("SOUL.md")
            switch vm.state {
            case .loading:
                ProgressView().tint(palette.primary)
            case .failed(let message):
                Text(message)
                    .font(LVTypography.caption.font)
                    .foregroundStyle(Color.lvTextMuted)
            case .loaded:
                TextEditor(text: Binding(
                    get: { vm.soulBody },
                    set: { vm.soulBody = $0 }
                ))
                .scrollContentBackground(.hidden)
                .font(LVTypography.mono.font)
                .frame(minHeight: 240)
                .padding(LVSpacing.sm)
                .background(palette.backgroundBase.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: LVRadius.md))
                HStack {
                    Spacer()
                    Button("Save") { Task { await vm.saveSoul() } }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.primary)
                        .disabled(vm.soulSaving)
                }
            }
        }
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            sectionLabel("Diagnostics")
            Text("Tailscale reachability isn't exposed to iOS apps. Pick the Tailscale mode above and enter your tailnet host manually; make sure the Tailscale app is connected first.")
                .font(LVTypography.caption.font)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(LVTypography.microTag.font.weight(.heavy))
            .tracking(0.8)
            .foregroundStyle(palette.textSecondary)
    }
}
