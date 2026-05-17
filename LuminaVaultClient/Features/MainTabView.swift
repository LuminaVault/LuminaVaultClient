// LuminaVaultClient/LuminaVaultClient/Features/MainTabView.swift
// HER-35: replaces the mascot-only stub. The Spaces tab is the home view —
// other tabs (Capture, Visual Search, Settings) ride future tickets.
import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            SpacesListView(vm: SpacesViewModel(spacesClient: spacesClient))
                .tabItem {
                    Label("Spaces", systemImage: "folder.fill")
                }

            home
                .tabItem {
                    Label("Home", systemImage: "sparkles")
                }
        }
        .tint(.lvCyan)
    }

    private var spacesClient: SpacesClientProtocol {
        SpacesHTTPClient(client: BaseHTTPClient(
            tokenProvider: { [appState] in appState.keychain.accessToken }
        ))
    }

    private var home: some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()
            VStack(spacing: 20) {
                HermieMascotView(state: .idle, size: 220, fallbackImageName: "OnboardingMascot")
                Text("LuminaVault")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(LinearGradient(
                        colors: [.lvAmber, .lvCyan],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text("Your memories, illuminated.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.lvTextSub)
            }
        }
        .lvBackground()
    }
}
