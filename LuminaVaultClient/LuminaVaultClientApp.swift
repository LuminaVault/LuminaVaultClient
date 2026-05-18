// LuminaVaultClient/LuminaVaultClient/LuminaVaultClientApp.swift
import SwiftUI
import AuthenticationServices
import GoogleSignIn

@main
struct LuminaVaultClientApp: App {
    @State private var appState = AppState()
    @State private var theme = LVThemeManager()
    @State private var showSplash = true
    @State private var biometricChecked = false
    @State private var captureCoordinator: CaptureCoordinator?
    @AppStorage("hasSeenGetStarted") private var hasSeenGetStarted = false
    @Environment(\.scenePhase) private var scenePhase

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
                            // HER-35: gate the home tab behind the explicit
                            // "Create My Vault" handshake. Legacy users
                            // (M37 backfill) skip this branch because the
                            // server starts them at vaultInitialized=true.
                            if appState.vaultInitialized {
                                MainTabView()
                                    .environment(\.captureCoordinator, captureCoordinator)
                            } else {
                                CreateVaultView(
                                    vm: CreateVaultViewModel(
                                        vaultClient: VaultHTTPClient(client: BaseHTTPClient(
                                            tokenProvider: { [appState] in appState.keychain.accessToken }
                                        )),
                                        appState: appState
                                    )
                                )
                            }
                        } else if !hasSeenGetStarted {
                            GetStartedView {
                                withAnimation { hasSeenGetStarted = true }
                            }
                        } else {
                            NavigationStack {
                                AuthLandingView(vm: makeAuthViewModel())
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
            // HER-209: foreground transitions trigger a credential-state poll.
            // `.active` fires on cold launch AND every return-to-foreground.
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await checkAppleCredentialState() }
                }
            }
            // HER-209: Apple emits this notification while the app is running
            // (e.g., user revokes from Settings without backgrounding).
            .task {
                for await _ in NotificationCenter.default.notifications(
                    named: ASAuthorizationAppleIDProvider.credentialRevokedNotification
                ) {
                    appState.signOut()
                }
            }
            // HER-34 — bring the capture coordinator up once the vault
            // is initialized. Stop it on sign-out so SwiftData / NWPath
            // resources don't leak across sessions.
            .task(id: appState.vaultInitialized) {
                if appState.vaultInitialized, captureCoordinator == nil {
                    let coord = CaptureCoordinator(
                        tokenProvider: { [appState] in appState.keychain.accessToken },
                    )
                    await coord.start()
                    captureCoordinator = coord
                } else if !appState.vaultInitialized, let coord = captureCoordinator {
                    await coord.stop()
                    captureCoordinator = nil
                }
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

    // HER-209 acceptance: "Revocation in iOS Settings logs the user out within
    // 5 s of next app foreground." `credentialState(forUserID:)` returns
    // sub-second on warm devices.
    private func checkAppleCredentialState() async {
        guard let userID = appState.keychain.appleUserId else { return }
        do {
            let state = try await ASAuthorizationAppleIDProvider()
                .credentialState(forUserID: userID)
            // `.notFound` mirrors `.revoked` for our purposes: the local Apple
            // ID can no longer satisfy our session, so we tear it down.
            if state == .revoked || state == .notFound {
                appState.signOut()
            }
        } catch {
            // Transient errors (e.g., no network at cold start) shouldn't sign
            // the user out — we'll re-check on the next foreground.
        }
    }
}
