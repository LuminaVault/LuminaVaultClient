// LuminaVaultClient/LuminaVaultClient/LuminaVaultClientApp.swift
import SwiftUI
import Sentry

import AuthenticationServices
import GoogleSignIn
import PostHog

// PostHog: reads POSTHOG_PROJECT_TOKEN and POSTHOG_HOST from the Xcode scheme
// Run environment variables. Set them under Product > Scheme > Edit Scheme >
// Run > Arguments > Environment Variables.
enum PostHogEnv: String {
    case projectToken = "POSTHOG_PROJECT_TOKEN"
    case host = "POSTHOG_HOST"

    var value: String {
        guard let value = ProcessInfo.processInfo.environment[rawValue] else {
            fatalError("Set \(rawValue) in the Xcode scheme Run environment variables.")
        }
        return value
    }
}

@main
struct LuminaVaultClientApp: App {
    @State private var appState = AppState()
    @State private var theme = LVThemeManager()
    @State private var showSplash = true
    @State private var biometricChecked = false
    @AppStorage("hasSeenGetStarted") private var hasSeenGetStarted = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SentrySDK.start { options in
            options.dsn = "https://a3a94645381ee5af35e404c7299e019c@o4510766840872960.ingest.de.sentry.io/4511406692368464"

            // Adds IP for users.
            // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
            options.sendDefaultPii = true

            // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
            // We recommend adjusting this value in production.
            options.tracesSampleRate = 1.0

            // Configure profiling. Visit https://docs.sentry.io/platforms/apple/profiling/ to learn more.
            options.configureProfiling = {
                $0.sessionSampleRate = 1.0 // We recommend adjusting this value in production.
                $0.lifecycle = .trace
            }

            // Uncomment the following lines to add more data to your events
            // options.attachScreenshot = true // This adds a screenshot to the error events
            // options.attachViewHierarchy = true // This adds the view hierarchy to the error events
            
            // Enable experimental logging features
            options.experimental.enableLogs = true
        }
        // Remove the next line after confirming that your Sentry integration is working.
        SentrySDK.capture(message: "This app uses Sentry! :)")

        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
           !clientID.isEmpty {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        // PostHog: initialize analytics SDK
        let config = PostHogConfig(
            apiKey: PostHogEnv.projectToken.value,
            host: PostHogEnv.host.value
        )
        config.captureApplicationLifecycleEvents = true
        PostHogSDK.shared.setup(config)
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
