import SwiftUI

#if DEBUG
/// Debug-only quick toggle that flips `BackendModeStore.current` between
/// `.localhost` and `.hosted` without leaving the auth screen. Reads the
/// real source of truth so it stays in sync with Settings → Server
/// Connection (which can also pick `.byo` / `.tailscale`).
struct EnvironmentTagView: View {
    @AppStorage(BackendModeStore.userDefaultsKey) private var currentModeRaw: String = ""
    @Environment(AppState.self) private var appState
    @State private var showPicker = false

    private var currentMode: BackendMode {
        BackendMode(rawValue: currentModeRaw) ?? BackendModeStore.current
    }

    var body: some View {
        Button(action: { showPicker = true }) {
            Text(displayName(for: currentMode))
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(background(for: currentMode))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(radius: 2)
        }
        .confirmationDialog("Select Environment", isPresented: $showPicker) {
            Button("Local") { select(.localhost) }
            Button("Prod") { select(.hosted) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Switching environments will sign you out.")
        }
    }

    private func select(_ mode: BackendMode) {
        guard mode != currentMode else { return }
        BackendModeStore.set(mode)
        Task { await appState.signOut() }
    }

    private func displayName(for mode: BackendMode) -> String {
        switch mode {
        case .localhost: return "Local"
        case .hosted: return "Prod"
        case .byo: return "BYO"
        case .tailscale: return "Tailscale"
        }
    }

    private func background(for mode: BackendMode) -> Color {
        switch mode {
        case .localhost: return .blue
        case .hosted: return .red
        case .byo, .tailscale: return .orange
        }
    }
}

#Preview {
    EnvironmentTagView()
        .environment(AppState())
}
#endif
