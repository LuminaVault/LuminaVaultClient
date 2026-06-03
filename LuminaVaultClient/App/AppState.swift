// LuminaVaultClient/LuminaVaultClient/App/AppState.swift
import Foundation
import LuminaVaultShared
import PostHog
import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppState {
    var isAuthenticated = false
    var currentUserId: UUID? = nil
    var currentEmail: String? = nil
    /// HER-35: gate flag. False after a fresh signup; flips true after the
    /// user completes the "Create My Vault" screen (or for any user whose
    /// `M37` backfill set them to true).
    var vaultInitialized = false
    /// HER-238: timestamp of the most recent successful `/v1/auth/me` fetch.
    /// `nil` means we've never refreshed since sign-in. Used by
    /// `refreshCurrentUserIfNeeded(authClient:now:)` to debounce.
    private(set) var lastMeFetchAt: Date?
    /// HER-238: minimum gap between background `/v1/auth/me` calls. Keeps
    /// rapid foreground transitions from hammering the auth server.
    static let meRefreshInterval: TimeInterval = 300
    let keychain: KeychainService
    let healthKit: HealthKitCoordinator?
    /// HER-39: process-wide SwiftData container backing the local vault
    /// inventory, sync queue, and sync log. Built lazily on first read so
    /// tests can override via the in-memory container.
    let modelContainer: ModelContainer
    /// HER-39: actor-isolated on-disk vault manager. Reads/writes go through
    /// here so the FS boundary stays single-owner.
    let localVault: LocalVaultManager
    /// HER-39: live reachability signal observed by the sync engine and
    /// status banner. Reads must happen on the main actor.
    let networkMonitor: NetworkMonitor
    /// HER-39: lazily-built offline sync engine. First touch wires HTTP
    /// clients, the SwiftData-backed queue, and the on-disk vault. Lives
    /// for the process lifetime once constructed.
    @ObservationIgnored private(set) lazy var syncManager: SyncManager = makeSyncManager()
    /// HER-39: feature-facing façade. UI code talks to the repository, never
    /// directly to `SyncManager` or the HTTP clients, so swapping the sync
    /// strategy stays a single-file change.
    @ObservationIgnored private(set) lazy var vaultRepository: VaultRepository = makeVaultRepository()
    /// HER-39: observable bridge of `SyncManager.state`. Subscribed exactly
    /// once via `bootstrapSyncObservation()` so SwiftUI can render the
    /// status banner + Settings row without each view spinning up its own
    /// observer.
    private(set) var syncState: SyncManager.SyncStateSnapshot = .idle
    // HER-237: process-wide single-flight refresh coordinator. Every
    // BaseHTTPClient minted via `makeHTTPClient()` shares it so concurrent
    // 401s collapse to one /v1/auth/refresh call.
    private let refreshCoordinator = TokenRefreshCoordinator()
    /// HER-185 — observable billing surface. Constructed lazily inside
    /// `handleAuthSuccess(_:)` so the RC `logIn` call and the
    /// `GET /v1/auth/me/billing` fetch are bound to a concrete user.
    /// `nil` between sign-out and the next sign-in; UI components that
    /// read tier state must tolerate this case.
    private(set) var billingService: BillingService?
    /// HER-185 — test-injectable factory for the RevenueCat-side adapter.
    /// Production defaults to `PurchasesProxyFactory.makeDefault()`, which
    /// returns a `LiveRevenueCatProxy` when `Purchases.configure(…)` ran
    /// or a `NoOpPurchasesProxy` when the RC key was absent/empty. Tests
    /// pass a `MockPurchasesProxy` so `BillingService` can be exercised
    /// without the RC SDK actually running.
    @ObservationIgnored var purchasesProxyFactory: @MainActor () -> PurchasesProxy = { PurchasesProxyFactory.makeDefault() }
    /// HER-211 — universal 402 → paywall presentation. Every
    /// `BaseHTTPClient` minted via `makeHTTPClient()` fires the
    /// `onPaymentRequired` callback on a 402; that callback sets this
    /// property, and `LuminaVaultClientApp` binds a root-level
    /// `.sheet(item:)` to it so the paywall presents regardless of
    /// which screen the failing call came from.
    var pendingPaywallID: PaywallPresentation?
    /// HER-214 — owns the POST/DELETE lifecycle for the APNS device
    /// token. Lazily built on first read so we don't spin up an HTTP
    /// client until a sign-in actually puts a token in flight.
    @ObservationIgnored private(set) lazy var deviceRegistration: DeviceRegistrationCoordinator = {
        DeviceRegistrationCoordinator(
            client: DeviceHTTPClient(client: makeHTTPClient())
        )
    }()
    /// HER-93 / HER-100 — server-tracked onboarding ladder. `nil` until
    /// `loadOnboardingState()` resolves on first authenticated launch.
    /// `LuminaVaultClientApp` reads `soulConfiguredCompleted` to decide
    /// whether to gate the main shell behind the SOUL.md quiz.
    var onboardingState: OnboardingStateDTO?
    private let sharedSessionKeychain = SharedSessionKeychain(accessGroup: Config.keychainAccessGroup)

    init(
        keychain: KeychainService = .shared,
        healthKit: HealthKitCoordinator? = nil,
        modelContainer: ModelContainer? = nil,
        localVault: LocalVaultManager = LocalVaultManager(),
        networkMonitor: NetworkMonitor? = nil
    ) {
        self.keychain = keychain
        self.healthKit = healthKit
        self.modelContainer = modelContainer ?? SwiftDataStack.makePersistent()
        self.localVault = localVault
        self.networkMonitor = networkMonitor ?? NetworkMonitor()
        let hasStoredSession = keychain.accessToken != nil
        self.isAuthenticated = hasStoredSession && !keychain.biometricsEnabled
        // Persisted users that re-launched the app have already cleared the
        // vault gate; assume `true` so legacy installs don't get bounced to
        // CreateVaultView. Fresh signups overwrite this in handleAuthSuccess.
        self.vaultInitialized = hasStoredSession
        if isAuthenticated {
            sharedSessionKeychain.accessToken = keychain.accessToken
            Task { await healthKit?.start() }
            startPhotoIndex()
            startCalendarSync()
        }
    }

    var needsBiometricUnlock: Bool {
        keychain.accessToken != nil && keychain.biometricsEnabled && !isAuthenticated
    }

    /// Apple Integration P0b — always-on device-RPC executor (lazily built,
    /// started on auth, listens for server→device commands over /v1/ws).
    private var deviceCommandExecutor: DeviceCommandExecutor?

    /// Apple Reminders selective-sync — lazily built, started on auth.
    /// Consent-gated on the `reminders` domain; pushes EventKit reminder
    /// deltas to the server cache the Hermes `reminders_list` tool reads.
    private var remindersSync: RemindersSyncCoordinator?

    /// Apple Photos derived-text index coordinator. Lazily built, started on
    /// auth alongside HealthKit; consent-gated on `.photos` before any scan.
    @ObservationIgnored private lazy var photoIndexCoordinator: PhotoIndexCoordinator = {
        let httpClient = makeHTTPClient()
        return PhotoIndexCoordinator(
            service: PhotoIndexService(client: httpClient),
            consentClient: AppleConsentHTTPClient(client: httpClient),
        )
    }()

    /// Fires a consent-gated Photos index scan. No-op (and no system prompt)
    /// unless the user has allowed the `.photos` domain.
    private func startPhotoIndex() {
        let coordinator = photoIndexCoordinator
        Task { await coordinator.start() }
    }

    /// Apple Calendar (EventKit) selective-sync — lazily built, started on
    /// auth, consent-gated on `.calendar`. Pushes derived event metadata to
    /// the server cache so Hermes can read the schedule in the background.
    private var calendarSyncCoordinator: CalendarSyncCoordinator?

    private func startCalendarSync() {
        if calendarSyncCoordinator == nil {
            let http = makeHTTPClient()
            calendarSyncCoordinator = CalendarSyncCoordinator(
                service: CalendarSyncService(httpClient: http),
                consentClient: AppleConsentHTTPClient(client: http),
            )
        }
        let coordinator = calendarSyncCoordinator
        Task { await coordinator?.start() }
    }

    /// Foreground trigger — re-pushes the EventKit window so the server cache
    /// stays fresh between background change notifications.
    func syncCalendarOnForeground() {
        let coordinator = calendarSyncCoordinator
        Task { await coordinator?.sync() }
    }

    func unlockStoredSession() {
        guard keychain.accessToken != nil else { return }
        isAuthenticated = true
        vaultInitialized = true
        Task { await healthKit?.start() }
        startDeviceCommandExecutor()
        startRemindersSync()
        startPhotoIndex()
        startCalendarSync()
    }

    private func startDeviceCommandExecutor() {
        if deviceCommandExecutor == nil {
            let keychain = self.keychain
            deviceCommandExecutor = DeviceCommandExecutor(
                baseURL: Config.apiBaseURL,
                tokenProvider: { @Sendable in keychain.accessToken },
                httpClient: makeHTTPClient(),
            )
        }
        let executor = deviceCommandExecutor
        Task { await executor?.start() }
    }

    /// Apple Reminders selective-sync — start on auth. Built lazily over a
    /// fresh HTTP client + AppleConsentHTTPClient; the coordinator self-gates
    /// on the `reminders` consent domain before touching EventKit.
    func startRemindersSync() {
        if remindersSync == nil {
            let httpClient = makeHTTPClient()
            remindersSync = RemindersSyncCoordinator(
                service: RemindersSyncService(httpClient: httpClient),
                consentClient: AppleConsentHTTPClient(client: httpClient),
            )
        }
        let coordinator = remindersSync
        Task { await coordinator?.start() }
    }

    /// App-foreground hook — re-pull reminders so edits made in the Reminders
    /// app while LuminaVault was backgrounded reach the cache.
    func syncRemindersOnForeground() {
        let coordinator = remindersSync
        Task { await coordinator?.sync() }
    }

    /// HER-39 — subscribes to `SyncManager` state changes and mirrors them
    /// into the main-actor `syncState` so SwiftUI observation flows. Safe
    /// to call repeatedly; subsequent calls re-replay the current snapshot.
    func bootstrapSyncObservation() {
        let manager = syncManager
        Task { [weak self] in
            await manager.addStateObserver { snapshot in
                Task { @MainActor in
                    self?.syncState = snapshot
                }
            }
        }
    }

    /// HER-39 — wires up the sync engine on first touch.
    private func makeSyncManager() -> SyncManager {
        let httpClient = makeHTTPClient()
        let queueStore = SyncQueueStore(modelContainer: modelContainer)
        return SyncManager(
            queue: queueStore,
            vaultClient: VaultHTTPClient(client: httpClient),
            kbCompileClient: KBCompileHTTPClient(client: httpClient),
            localVault: localVault,
            networkMonitor: networkMonitor
        )
    }

    private func makeVaultRepository() -> VaultRepository {
        let httpClient = makeHTTPClient()
        return VaultRepository(
            syncManager: syncManager,
            kbCompileClient: KBCompileHTTPClient(client: httpClient),
            vaultClient: VaultHTTPClient(client: httpClient),
            networkMonitor: networkMonitor,
            modelContainer: modelContainer,
            localVault: localVault,
            tenantIDProvider: { [weak self] in self?.currentUserId }
        )
    }

    /// HER-237 — produces a `BaseHTTPClient` wired with token injection,
    /// 401 auto-refresh, and a sign-out trigger when refresh fails. All
    /// per-feature HTTP clients (Vault, Spaces, Memory, Settings, …) MUST
    /// be built through this factory so they share the refresh coordinator.
    func makeHTTPClient() -> BaseHTTPClient { sharedHTTPClient }

    /// HER perf audit (C1a): `BaseHTTPClient` is `final … Sendable` with only
    /// `let` stored state, so one instance is safe to share process-wide.
    /// Memoized so `makeHTTPClient()` stops allocating three objects (bootstrap
    /// + `AuthHTTPClient` + `BaseHTTPClient`) on every SwiftUI `body` eval —
    /// `MainTabView` rebuilds every per-feature client on each tab switch.
    @ObservationIgnored private lazy var sharedHTTPClient: BaseHTTPClient = buildHTTPClient()

    private func buildHTTPClient() -> BaseHTTPClient {
        let keychain = self.keychain
        let sharedSessionKeychain = self.sharedSessionKeychain
        let coordinator = self.refreshCoordinator
        // Bootstrap client used solely for `/v1/auth/refresh`. Has no
        // refresh handler of its own, so a 401 on the refresh call itself
        // propagates as `.unauthorized` and the outer client signs the
        // user out.
        let bootstrap = BaseHTTPClient(tokenProvider: { nil })
        let authClient = AuthHTTPClient(client: bootstrap)

        return BaseHTTPClient(
            tokenProvider: { keychain.accessToken },
            refreshHandler: {
                guard let token = keychain.refreshToken else {
                    throw APIError.unauthorized
                }
                let response = try await authClient.refreshToken(token)
                keychain.accessToken = response.accessToken
                keychain.refreshToken = response.refreshToken
                sharedSessionKeychain.accessToken = response.accessToken
                return response.accessToken
            },
            onAuthFailure: { [weak self] in
                await self?.signOut()
            },
            onPaymentRequired: { [weak self] paywallID, _ in
                // HER-211 — root-level paywall presentation. The server's
                // hint (or "default") drives which RC offering renders;
                // `LuminaVaultClientApp` binds a `.sheet(item:)` to
                // `pendingPaywallID` so this hops onto the main actor
                // and surfaces the sheet wherever the user is.
                await MainActor.run {
                    self?.pendingPaywallID = PaywallPresentation(id: paywallID ?? "default")
                }
            },
            refreshCoordinator: coordinator
        )
    }

    /// HER-107 — Conversations client factory. Mirrors `makeHTTPClient()`
    /// so the Conversations endpoints share the refresh coordinator and
    /// the bearer-token provider. Used by the chat surface in the Think
    /// tab.
    func makeConversationsClient() -> any ConversationsClientProtocol {
        ConversationsHTTPClient(client: makeHTTPClient())
    }

    /// HER-107 — non-streaming chat client (BYO-Hermes-aware
    /// `/v1/chat/completions`). Paired with the conversations client as
    /// the "fresh" transport in the chat surface's mode toggle.
    func makeChatClient() -> any ChatClientProtocol {
        ChatHTTPClient(client: makeHTTPClient())
    }

    /// HER-154 — daily review digest client (GET /v1/me/today). Pull-
    /// to-refresh and tab-appear consumers go through this factory so
    /// they share the bearer + 401 refresh coordinator.
    func makeDailyReviewClient() -> any DailyReviewClientProtocol {
        DailyReviewHTTPClient(client: makeHTTPClient())
    }

    /// HER-293 / HER-108 — kb-compile HTTP client (POST `/v1/kb-compile`
    /// and `GET /v1/kb-compile/pending`). Used by `SyncAndLearnViewModel`
    /// to drive the disable-on-zero state.
    func makeKBCompileClient() -> any KBCompileClientProtocol {
        KBCompileHTTPClient(client: makeHTTPClient())
    }

    /// HER-288 / HER-108 — WS subscription to `/v1/ws` decoded as
    /// `KBCompileProgressEvent` frames. Token provider is read fresh per
    /// connect attempt so token refreshes propagate without recreating
    /// the client.
    func makeKBCompileWebSocketClient() -> any KBCompileWebSocketClientProtocol {
        let keychain = self.keychain
        return KBCompileWebSocketClient(
            baseURL: Config.apiBaseURL,
            tokenProvider: { @Sendable in keychain.accessToken },
        )
    }

    /// HER-290 / HER-108 — memory HTTP client (PATCH approve/reject).
    func makeMemoryClient() -> any MemoryClientProtocol {
        MemoryHTTPClient(client: makeHTTPClient())
    }

    func makeBillingClient() -> any BillingClientProtocol {
        BillingHTTPClient(client: makeHTTPClient())
    }

    func handleAuthSuccess(_ response: AuthResponse) {
        keychain.accessToken = response.accessToken
        keychain.refreshToken = response.refreshToken
        sharedSessionKeychain.accessToken = response.accessToken
        currentUserId = response.userId
        currentEmail = response.email
        vaultInitialized = response.vaultInitialized
        isAuthenticated = true
        Task { await healthKit?.start() }
        startPhotoIndex()
        startCalendarSync()
        // PostHog: identify user so all subsequent events are attributed to them
        // Prefer email if present; otherwise fall back to userId
        let distinctId = response.email ?? response.userId.uuidString
        var userProps: [String: Any] = [:]
        userProps["email"] = response.email
        PostHogSDK.shared.identify(distinctId, userProperties: userProps)
        // HER-185 — bind RC identity to the server-side user and pull the
        // authoritative billing snapshot. Service stays nil until the
        // first sign-in so cold-launch + unauthenticated paths skip RC.
        let billing = BillingService(
            client: makeBillingClient(),
            purchases: purchasesProxyFactory()
        )
        billingService = billing
        Task { await billing.bootstrap(userID: response.userId) }
    }

    /// HER-214 — DELETE the registered APNS device-token row BEFORE the
    /// keychain is wiped so the call still has a valid bearer. Failures
    /// are logged and swallowed by the coordinator; the local sign-out
    /// proceeds either way.
    func signOut() async {
        await deviceRegistration.unregisterCurrentToken()
        // PostHog: capture sign-out then reset the anonymous distinct ID
        PostHogSDK.shared.capture("user_signed_out")
        PostHogSDK.shared.reset()
        Task { await healthKit?.stop() }
        remindersSync?.stop()
        remindersSync = nil
        calendarSyncCoordinator?.stop()
        calendarSyncCoordinator = nil
        // HER-185 — tear down RC identity + customer-info stream before we
        // drop the user from local state. Snapshot the service so the
        // detached task can run after `billingService` is nilled out.
        if let billing = billingService {
            Task { await billing.teardown() }
        }
        billingService = nil
        sharedSessionKeychain.clear()
        keychain.clearAll()
        currentUserId = nil
        currentEmail = nil
        vaultInitialized = false
        isAuthenticated = false
        lastMeFetchAt = nil
        onboardingState = nil
    }

    /// HER-100 — Onboarding state HTTP client factory. Used by the SOUL
    /// quiz gate to read the current ladder and by the confirm step to
    /// latch `soulConfiguredCompleted` on save.
    func makeOnboardingClient() -> any OnboardingClientProtocol {
        OnboardingHTTPClient(client: makeHTTPClient())
    }

    /// HER-300 — LLM preferences client factory (`GET`/`PUT
    /// /v1/me/preferences/llm`). The Choose-Your-Brain onboarding gate
    /// and the Settings → Intelligence pane both build off this; sharing
    /// the factory keeps the refresh-coordinator-aware HTTP client
    /// consistent.
    func makeLLMPreferencesClient() -> LLMPreferencesHTTPClient {
        LLMPreferencesHTTPClient(client: makeHTTPClient())
    }

    /// HER-300 — Providers client factory (per-user credential CRUD for
    /// the BYOK flow). Used by the Choose-Your-Brain gate to push the
    /// existing `ProvidersPaneView` when the user selects "Use my own
    /// API key", so onboarding can reuse the live Settings surface
    /// instead of duplicating credential UI.
    func makeProvidersClient() -> any ProvidersClientProtocol {
        ProvidersHTTPClient(client: makeHTTPClient())
    }

    /// HER-100 — SOUL.md client factory. Mirrors the existing
    /// `SoulHTTPClient` wiring used by Settings → Server Connection so
    /// the quiz confirm step can `PUT /v1/soul` against the same
    /// refresh-coordinator-aware HTTP client.
    func makeSoulClient() -> any SoulClientProtocol {
        SoulHTTPClient(client: makeHTTPClient())
    }

    /// HER-93 — pull the current onboarding ladder from the server.
    /// Debounce-free: callers (`LuminaVaultClientApp.task(id: isAuthenticated)`)
    /// invoke this once per sign-in, and the SOUL confirm step refreshes
    /// the snapshot on successful save by handing back the patched DTO.
    func loadOnboardingState() async {
        guard isAuthenticated else { return }
        do {
            onboardingState = try await makeOnboardingClient().get()
        } catch APIError.unauthorized {
            // HER-237 already drove sign-out; nothing left to do.
        } catch {
            // Network / 5xx — keep stale (or nil) state; the gate
            // tolerates `nil` by deferring the quiz until the next
            // fetch succeeds.
        }
    }

    /// HER-238 — fetch `/v1/auth/me` on app resume to keep `currentUserId`
    /// and `currentEmail` in sync with the server. Debounced via
    /// `meRefreshInterval` so rapid foreground transitions don't hammer
    /// the auth server.
    ///
    /// - 401: silently ignored. The HER-237 interceptor will already have
    ///   driven a sign-out by the time this returns, so there's nothing
    ///   more to do here.
    /// - Other failures (network, 5xx): logged via the caller (we don't
    ///   surface UI errors for a background refresh) and the stale state
    ///   is preserved.
    func refreshCurrentUserIfNeeded(
        authClient: AuthClientProtocol,
        now: Date = .now
    ) async {
        guard isAuthenticated else { return }
        if let last = lastMeFetchAt,
           now.timeIntervalSince(last) < Self.meRefreshInterval {
            return
        }
        do {
            let me = try await authClient.getMe()
            lastMeFetchAt = now
            let emailChanged = (currentEmail != me.email)
            if currentUserId != me.userId { currentUserId = me.userId }
            if emailChanged { currentEmail = me.email }
            // Re-identify with PostHog only when the email moved; otherwise
            // we'd spam identify on every foreground.
            if emailChanged {
                PostHogSDK.shared.identify(me.email, userProperties: ["email": me.email])
            }
        } catch APIError.unauthorized {
            // HER-237 interceptor already signed user out — nothing left to do.
        } catch {
            // Network / 5xx — keep stale state.
        }
    }
}
