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
    private let soulClient: SoulClientProtocol

    init(soulClient: SoulClientProtocol) {
        self.soulClient = soulClient
        self.mode = BackendModeStore.current
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
                VStack(alignment: .leading, spacing: 20) {
                    modeSection
                    soulSection
                    debugSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Server Connection")
        .lvBackground()
        .task { await vm.load() }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Backend mode")
            VStack(spacing: 8) {
                ForEach(BackendMode.allCases) { mode in
                    Button {
                        vm.setMode(mode)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.label)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Text(mode.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            if vm.mode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(palette.primary)
                            }
                        }
                        .padding(12)
                        .background(palette.backgroundBase.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(vm.mode == mode ? palette.primary : palette.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Per-mode URL is configured in Advanced → Hermes Gateway (HER-218).")
                .font(.system(size: 11))
                .foregroundStyle(Color.lvTextMuted)
        }
    }

    private var soulSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SOUL.md")
            switch vm.state {
            case .loading:
                ProgressView().tint(palette.primary)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.lvTextMuted)
            case .loaded:
                TextEditor(text: Binding(
                    get: { vm.soulBody },
                    set: { vm.soulBody = $0 }
                ))
                .scrollContentBackground(.hidden)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .padding(8)
                .background(palette.backgroundBase.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Diagnostics")
            Text("Tailscale reachability isn't exposed to iOS apps. If you're on Tailscale, set the host manually in Hermes Gateway.")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(palette.textSecondary)
    }
}
