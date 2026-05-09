// LuminaVaultClient/LuminaVaultClient/LuminaVaultClientApp.swift
import SwiftUI

@main
struct LuminaVaultClientApp: App {
    @State private var appState = AppState()
    @State private var theme = LVThemeManager()
    @State private var showSplash = true
    @State private var biometricChecked = false

    private var authClient: AuthHTTPClient {
        AuthHTTPClient(client: BaseHTTPClient(
            tokenProvider: { [appState] in appState.keychain.accessToken }
        ))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    LVSplashView()
                        .transition(.opacity)
                } else {
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
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: showSplash)
            .preferredColorScheme(theme.appearance.colorSchemeOverride)
            .environment(appState)
            .environment(theme)
            .task {
                // Biometrics check
                guard !biometricChecked else { return }
                biometricChecked = true
                if !appState.isAuthenticated,
                   appState.keychain.biometricsEnabled,
                   appState.keychain.accessToken != nil {
                    let ok = await BiometricsService.shared.authenticate(reason: "Unlock LuminaVault")
                    if ok { appState.isAuthenticated = true }
                }
                // Dismiss splash after minimum display time
                try? await Task.sleep(for: .seconds(2.0))
                withAnimation { showSplash = false }
            }
        }
    }
}
