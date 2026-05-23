// LuminaVaultClient/LuminaVaultClient/LuminaVaultClientApp.swift
import SwiftUI
import Sentry

import AuthenticationServices
import GoogleSignIn
import PostHog
import RevenueCat

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
    @UIApplicationDelegateAdaptor(NotificationsAppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var theme = LVThemeManager()
    @State private var notificationRouter = NotificationRouter()
    @State private var workspaceSelection = WorkspaceSelection()
    @State private var showSplash = true
    @State private var biometricChecked = false
    @State private var captureCoordinator: CaptureCoordinator?
    @AppStorage("hasSeenGetStarted") private var hasSeenGetStarted = false
    // HER-287 — local flag for the conversion-funnel completion. Sits
    // between vault-create and SOUL quiz. UserDefaults-backed so the
    // user only sees it once across reinstalls only if the device-id
    // store gets wiped (per-install scope is good enough for v1).
    @AppStorage("hasSeenConversionFunnel") private var hasSeenConversionFunnel = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SentrySDK.start { options in
            options.dsn = Config.sentryDSN ?? "https://a3a94645381ee5af35e404c7299e019c@o4510766840872960.ingest.de.sentry.io/4511406692368464"
            if let environment = Config.sentryEnvironment {
                options.environment = environment
            }

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

        // HER-185 — RevenueCat SDK. Soft failure on missing key (paywall
        // ticket renders gracefully; server-truth billing still flows
        // via /v1/auth/me/billing).
        if let rcKey = Config.revenueCatPublicKey {
            #if DEBUG
            Purchases.logLevel = .info
            #else
            Purchases.logLevel = .warn
            #endif
            Purchases.configure(with: Configuration.Builder(withAPIKey: rcKey).build())
        } else {
            SentrySDK.capture(message: "RevenueCat key missing — billing disabled for this launch")
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
                                // HER-287 — conversion-funnel questionnaire
                                // gates between vault-create and SOUL quiz.
                                // Local-only flag (no server latch);
                                // running it again is harmless if a user
                                // ever resets defaults.
                                let needsConversionFunnel = !hasSeenConversionFunnel
                                // HER-100: gate the main shell behind the
                                // SOUL.md 5-step quiz. We only require
                                // completion when the server's onboarding
                                // ladder has loaded AND reports
                                // `soulConfiguredCompleted == false`. A
                                // nil ladder (cold-launch race, network
                                // failure) defaults to showing the main
                                // shell so the user is never locked out;
                                // the next foreground re-attempts the
                                // load and gates if appropriate.
                                let needsSoulQuiz = appState.onboardingState?.soulConfiguredCompleted == false
                                if needsConversionFunnel {
                                    ConversionFunnelContainer { summary in
                                        // HER-287 → HER-211 handoff: flip
                                        // the local flag so the funnel
                                        // never re-presents, then trigger
                                        // the universal root paywall.
                                        //
                                        // HER-295 — emit the funnel
                                        // completion + paywall-shown
                                        // events so the PostHog funnel
                                        // chart closes out with the same
                                        // distinct_id PostHog already
                                        // bound via `identify` in
                                        // AppState.handleAuthSuccess.
                                        let telemetry = ConversionFunnelTelemetry()
                                        telemetry.completed(summary: summary)
                                        hasSeenConversionFunnel = true
                                        let paywallID = "default"
                                        appState.pendingPaywallID = PaywallPresentation(id: paywallID)
                                        telemetry.paywallShown(paywallID: paywallID)
                                    }
                                } else if needsSoulQuiz {
                                    SoulQuizContainerView(
                                        state: SoulQuizState(userId: appState.currentUserId),
                                        soulClient: appState.makeSoulClient(),
                                        onboardingClient: appState.makeOnboardingClient()
                                    ) { updated in
                                        appState.onboardingState = updated
                                        // HER-214 (per ticket) — the UN-authorization
                                        // prompt lands AFTER the SOUL quiz, BEFORE
                                        // the main app shell takes over. Fire-and-
                                        // forget: granted permission flows through
                                        // `NotificationsAppDelegate` →
                                        // `deviceRegistration.register(tokenHex:)`
                                        // so the POST happens automatically.
                                        Task {
                                            await appDelegate.requestAuthorizationAndRegister()
                                            if let hex = appDelegate.deviceTokenHex {
                                                await appState.deviceRegistration.register(tokenHex: hex)
                                            }
                                        }
                                    }
                                } else {
                                    MainTabView()
                                        .environment(\.captureCoordinator, captureCoordinator)
                                }
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
                    .safeAreaInset(edge: .bottom) {
                        #if DEBUG
                        if !showSplash && !appState.isAuthenticated {
                            EnvironmentTagView()
                                .padding(.bottom, 8)
                        }
                        #endif
                    }
                }
            }
            .animation(.easeInOut(duration: 0.4), value: showSplash)
            .animation(.easeInOut(duration: 0.4), value: hasSeenGetStarted)
            .lvThemed(theme)
            .environment(appState)
            .environment(theme)
            .environment(notificationRouter)
            .environment(workspaceSelection)
            // HER-211 — universal 402 interceptor presents the paywall at
            // the root regardless of which tab/screen the failing call
            // originated from. AppState publishes `pendingPaywallID`
            // from the BaseHTTPClient `onPaymentRequired` callback.
            .sheet(
                item: Binding(
                    get: { appState.pendingPaywallID },
                    set: { appState.pendingPaywallID = $0 }
                )
            ) { presentation in
                PaywallView(paywallID: presentation.id)
                    .environment(appState)
                    .environment(theme)
            }
            .task {
                // HER-179 — bridge the AppDelegate to the SwiftUI-side
                // router so taps deep-link into the right surface.
                //
                // HER-214 — install the device-registration coordinator
                // as the APNS token observer. The UN-authorization prompt
                // itself fires from `SoulQuizContainerView` on save (see
                // the `onCompleted` closure on the gate above) so it lands
                // at the ticket-correct "after SOUL.md quiz" moment for
                // fresh sign-ups.
                appDelegate.router = notificationRouter
                appDelegate.onTokenAvailable = appState.deviceRegistration
            }
            // HER-214 — warm-launch path only. If the system has already
            // granted notification permission on a previous run, APNS
            // hands us a token before any UI mounts; re-POST it so the
            // server row stays current. New sign-ups whose permission
            // status is still `.notDetermined` will see the prompt land
            // from the SOUL confirm step, not here.
            //
            // HER-100 — pull the onboarding ladder so the SOUL quiz gate
            // above renders the right surface on this sign-in.
            .task(id: appState.isAuthenticated) {
                guard appState.isAuthenticated else { return }
                if let hex = appDelegate.deviceTokenHex {
                    await appState.deviceRegistration.register(tokenHex: hex)
                }
                await appState.loadOnboardingState()
                // HER-214 — covers the "returning user on a new device"
                // case where the SOUL quiz is bypassed (server already
                // reports `soulConfiguredCompleted == true`) but the
                // notification authorization status is still
                // `.notDetermined`. Fresh sign-ups still get the prompt
                // from the SoulQuizContainerView `onCompleted` closure
                // above; this hook only fires when the quiz is skipped.
                if appState.onboardingState?.soulConfiguredCompleted == true,
                   await NotificationsAppDelegate.shouldRequestAuthorization() {
                    await appDelegate.requestAuthorizationAndRegister()
                    if let hex = appDelegate.deviceTokenHex {
                        await appState.deviceRegistration.register(tokenHex: hex)
                    }
                }
            }
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
                    await appState.signOut()
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
                await appState.signOut()
            }
        } catch {
            // Transient errors (e.g., no network at cold start) shouldn't sign
            // the user out — we'll re-check on the next foreground.
        }
    }
}
