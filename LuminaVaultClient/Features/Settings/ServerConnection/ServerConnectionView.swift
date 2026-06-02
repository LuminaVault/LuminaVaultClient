// LuminaVaultClient/LuminaVaultClient/Features/Settings/ServerConnection/ServerConnectionView.swift
//
// HER-250 — Settings → Server Connection. Backend mode picker + SOUL.md
// editor. Tailscale reachability detection is best-effort (manual host
// entry today; iOS doesn't expose tailnet state directly). Backend-mode
// hot-swap is deferred — the picker just persists the user choice; the
// existing HermesGateway pane (HER-218) handles override URLs today.

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
    private let soulClient: SoulClientProtocol
    private let healthClient: HealthClientProtocol

    init(soulClient: SoulClientProtocol, healthClient: HealthClientProtocol = HealthHTTPClient()) {
        self.soulClient = soulClient
        self.healthClient = healthClient
        self.mode = BackendModeStore.current
        self.byoURLInput = BYOServerStore.url?.absoluteString ?? ""
    }

    /// Caution banner when the typed BYO URL trades away transport security.
    var byoTransportWarning: String? {
        URLValidation.transportWarning(for: byoURLInput)
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

    func load() async {
        state = .loading
        do {
            let response = try await soulClient.get()
            soulBody = response.body
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
            let response = try await soulClient.put(SoulMdPutRequest(body: soulBody))
            soulBody = response.body
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
            Text("Tailscale URLs are configured in Advanced → Hermes Gateway (HER-218).")
                .font(LVTypography.caption.font)
                .foregroundStyle(Color.lvTextMuted)
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
            Text("Tailscale reachability isn't exposed to iOS apps. If you're on Tailscale, set the host manually in Hermes Gateway.")
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
