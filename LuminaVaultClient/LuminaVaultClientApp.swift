// LuminaVaultClient/LuminaVaultClient/LuminaVaultClientApp.swift
import SwiftUI
import Sentry

import AuthenticationServices
import GoogleSignIn
import PostHog

// PostHog: resolves POSTHOG_PROJECT_TOKEN / POSTHOG_HOST at runtime.
//
// HER-242 — production builds installed via TestFlight / Ad-Hoc don't see
// the Xcode scheme env vars (those only flow when launched by the Xcode
// debugger). The previous implementation fatalError'd on init and crashed
// the app on every cold launch in production. Resolution order is now:
//   1. `Bundle.main` Info.plist (set via `INFOPLIST_KEY_*` build settings
//      or xcconfig — preferred path for prod).
//   2. `ProcessInfo.environment` (scheme env vars — local dev keeps
//      working unchanged).
//   3. Compile-time defaults — the PostHog project token is a public
//      identifier (used by every client; documented as embeddable), so
//      shipping it in source is intentional and matches what was already
//      committed to the scheme files.
// If every source is empty, PostHog is left uninitialized rather than
// crashing — Sentry still captures and the app boots.
enum PostHogEnv: String {
    case projectToken = "POSTHOG_PROJECT_TOKEN"
    case host = "POSTHOG_HOST"

    var value: String? {
        if let v = Bundle.main.object(forInfoDictionaryKey: rawValue) as? String,
           !v.isEmpty {
            return v
        }
        if let v = ProcessInfo.processInfo.environment[rawValue], !v.isEmpty {
            return v
        }
        return Self.defaults[rawValue]
    }

    private static let defaults: [String: String] = [
        "POSTHOG_PROJECT_TOKEN": "phc_uJu7ZqyfuPpDAsWpyzNiPH2pow8kdUfNVQVM2PEUCFGU",
        "POSTHOG_HOST": "https://us.i.posthog.com",
    ]
}

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
        // PostHog: initialize analytics SDK only when both config values
        // resolve. HER-242 — never crash on missing config in production;
        // surface the gap to Sentry instead and continue booting.
        if let token = PostHogEnv.projectToken.value,
           let host = PostHogEnv.host.value {
            let config = PostHogConfig(apiKey: token, host: host)
            config.captureApplicationLifecycleEvents = true
            PostHogSDK.shared.setup(config)
        } else {
            SentrySDK.capture(message: "PostHog config missing — analytics disabled for this launch")
        }

        // HER-39: register BGTaskScheduler identifiers before any scene
        // activates. Must happen synchronously from `init` so the system
        // can resolve the identifiers during scene setup.
        BackgroundSyncRegistrar.register()
    }

    private var authClient: AuthHTTPClient {
        AuthHTTPClient(client: appState.makeHTTPClient())
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
                                        vaultClient: VaultHTTPClient(client: appState.makeHTTPClient()),
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
            // HER-238: same hook refreshes the current user from /v1/auth/me
            // (debounced) so server-side profile changes flow into AppState.
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await checkAppleCredentialState() }
                    Task {
                        await appState.refreshCurrentUserIfNeeded(authClient: authClient)
                    }
                } else if newPhase == .background {
                    // HER-39: arm the next BGTaskScheduler runs so the sync
                    // engine can drain its queue while the app is suspended.
                    BackgroundSyncRegistrar.scheduleNext()
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
                // HER-39 — once AppState is alive, hand the sync engine
                // to the BGTaskScheduler so a background task fired by the
                // system drains the queue. Idempotent reassignment is safe.
                BackgroundSyncRegistrar.drainHandler = { [appState] in
                    guard let tenantID = appState.currentUserId else { return }
                    await appState.syncManager.runUntilDrained(tenantID: tenantID)
                }
                // HER-39 — observe SyncManager state changes so the banner +
                // Settings row reflect live progress.
                appState.bootstrapSyncObservation()
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
