// LuminaVaultClient/LuminaVaultClient/LuminaVaultClientApp.swift
import SwiftUI

@main
struct LuminaVaultClientApp: App {
    @State private var appState = AppState()
    @State private var biometricChecked = false

    private var authClient: AuthHTTPClient {
        AuthHTTPClient(client: BaseHTTPClient(
            tokenProvider: { [appState] in appState.keychain.accessToken }
        ))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAuthenticated {
                    MainTabView()
                } else {
                    NavigationStack {
                        SignInView(vm: AuthViewModel(
                            authClient: authClient,
                            appState: appState
                        ))
                    }
                }
            }
            .environment(appState)
            .task {
                guard !biometricChecked else { return }
                biometricChecked = true
                if !appState.isAuthenticated,
                   appState.keychain.biometricsEnabled,
                   appState.keychain.accessToken != nil {
                    let ok = await BiometricsService.shared.authenticate(reason: "Unlock LuminaVault")
                    if ok { appState.isAuthenticated = true }
                }
            }
        }
    }
}
