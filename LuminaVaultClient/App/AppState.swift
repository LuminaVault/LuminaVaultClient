// LuminaVaultClient/LuminaVaultClient/App/AppState.swift
import Foundation
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
        self.isAuthenticated = keychain.accessToken != nil
        // Persisted users that re-launched the app have already cleared the
        // vault gate; assume `true` so legacy installs don't get bounced to
        // CreateVaultView. Fresh signups overwrite this in handleAuthSuccess.
        self.vaultInitialized = keychain.accessToken != nil
        if isAuthenticated {
            Task { await healthKit?.start() }
        }
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
    func makeHTTPClient() -> BaseHTTPClient {
        let keychain = self.keychain
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
                return response.accessToken
            },
            onAuthFailure: { [weak self] in
                await MainActor.run { self?.signOut() }
            },
            refreshCoordinator: coordinator
        )
    }

    func handleAuthSuccess(_ response: AuthResponse) {
        keychain.accessToken = response.accessToken
        keychain.refreshToken = response.refreshToken
        currentUserId = response.userId
        currentEmail = response.email
        vaultInitialized = response.vaultInitialized
        isAuthenticated = true
        Task { await healthKit?.start() }
        // PostHog: identify user so all subsequent events are attributed to them
        // Prefer email if present; otherwise fall back to userId
        let distinctId = response.email ?? response.userId.uuidString
        var userProps: [String: Any] = [:]
        userProps["email"] = response.email
        PostHogSDK.shared.identify(distinctId, userProperties: userProps)
    }

    func signOut() {
        // PostHog: capture sign-out then reset the anonymous distinct ID
        PostHogSDK.shared.capture("user_signed_out")
        PostHogSDK.shared.reset()
        Task { await healthKit?.stop() }
        keychain.clearAll()
        currentUserId = nil
        currentEmail = nil
        vaultInitialized = false
        isAuthenticated = false
        lastMeFetchAt = nil
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

