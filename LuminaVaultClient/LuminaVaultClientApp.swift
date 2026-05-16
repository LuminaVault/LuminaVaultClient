// LuminaVaultClient/LuminaVaultClient/LuminaVaultClientApp.swift
import SwiftUI
import GoogleSignIn

@main
struct LuminaVaultClientApp: App {
    @State private var appState = AppState()
    @State private var theme = LVThemeManager()
    @State private var showSplash = true
    @State private var biometricChecked = false
    @AppStorage("hasSeenGetStarted") private var hasSeenGetStarted = false

    init() {
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
           !clientID.isEmpty {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    private var authClient: AuthHTTPClient {
        AuthHTTPClient(client: BaseHTTPClient(
            tokenProvider: { [appState] in appState.keychain.accessToken }
        ))
    }

    private func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(
            authClient: authClient,
            appState: appState,
            appleService: AppleSignInService(),
            googleService: GoogleSignInService(),
            xService: XSignInService()
        )
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
                        } else if !hasSeenGetStarted {
                            GetStartedView {
                                withAnimation { hasSeenGetStarted = true }
                            }
                        } else {
                            NavigationStack {
                                SignInView(vm: makeAuthViewModel())
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: showSplash)
            .animation(.easeInOut(duration: 0.4), value: hasSeenGetStarted)
            .preferredColorScheme(theme.appearance.colorSchemeOverride)
            .environment(appState)
            .environment(theme)
            .onOpenURL { url in
                _ = GIDSignIn.sharedInstance.handle(url)
            }
            .task {
                guard !biometricChecked else { return }
                biometricChecked = true
                if !appState.isAuthenticated,
                   appState.keychain.biometricsEnabled,
                   appState.keychain.accessToken != nil {
                    let ok = await BiometricsService.shared.authenticate(reason: "Unlock LuminaVault")
                    if ok { appState.isAuthenticated = true }
                }
                try? await Task.sleep(for: .seconds(2.0))
                withAnimation { showSplash = false }
            }
        }
    }
}
