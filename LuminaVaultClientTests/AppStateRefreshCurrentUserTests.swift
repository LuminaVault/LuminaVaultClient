// LuminaVaultClient/LuminaVaultClientTests/AppStateRefreshCurrentUserTests.swift
// HER-238 — coverage for `AppState.refreshCurrentUserIfNeeded(authClient:now:)`.
import XCTest
@testable import LuminaVaultClient

@MainActor
final class AppStateRefreshCurrentUserTests: XCTestCase {
    private var state: AppState!
    private var mock: MockAuthClient!
    private let signedInUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    override func setUp() {
        super.setUp()
        state = AppState(keychain: KeychainService(service: "test.her238.\(UUID().uuidString)"))
        mock = MockAuthClient()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "lv.active-vault.\(signedInUserId.uuidString)")
        state = nil
        mock = nil
        super.tearDown()
    }

    func testRefreshUpdatesEmailWhenServerValueChanged() async {
        await signIn()
        mock.getMeResult = .success(MeResponse(
            userId: signedInUserId,
            email: "renamed@example.com",
            username: "tester",
            isVerified: true,
            privacyNoCNOrigin: false,
            contextRouting: true
        ))

        XCTAssertEqual(state.currentEmail, "test@example.com")
        await state.refreshCurrentUserIfNeeded(authClient: mock, now: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(state.currentEmail, "renamed@example.com")
        XCTAssertEqual(mock.getMeCallCount, 1)
        XCTAssertNotNil(state.lastMeFetchAt)
    }

    func testRefreshIsDebouncedWithinFiveMinutes() async {
        await signIn()
        let t0 = Date(timeIntervalSince1970: 10_000)
        await state.refreshCurrentUserIfNeeded(authClient: mock, now: t0)
        XCTAssertEqual(mock.getMeCallCount, 1)

        // 4 min 59 s later — still inside the window.
        await state.refreshCurrentUserIfNeeded(
            authClient: mock,
            now: t0.addingTimeInterval(299)
        )
        XCTAssertEqual(mock.getMeCallCount, 1, "Debounce window must skip the network call")

        // 5 min 1 s later — past the window.
        await state.refreshCurrentUserIfNeeded(
            authClient: mock,
            now: t0.addingTimeInterval(301)
        )
        XCTAssertEqual(mock.getMeCallCount, 2)
    }

    func testRefreshSkipsWhenSignedOut() async {
        await signIn()
        await state.signOut()
        await state.refreshCurrentUserIfNeeded(authClient: mock, now: .now)
        XCTAssertEqual(mock.getMeCallCount, 0)
    }

    func testRefreshFailureKeepsStaleState() async {
        await signIn()
        struct NetBoom: Error {}
        mock.getMeResult = .failure(NetBoom())

        let emailBefore = state.currentEmail
        let userIdBefore = state.currentUserId
        await state.refreshCurrentUserIfNeeded(authClient: mock, now: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(state.currentEmail, emailBefore, "Stale email preserved on network failure")
        XCTAssertEqual(state.currentUserId, userIdBefore)
        XCTAssertNil(state.lastMeFetchAt, "Failed fetch must not advance the debounce timestamp")
        XCTAssertTrue(state.isAuthenticated, "Failed fetch must not sign user out")
    }

    func testRefreshOnUnauthorizedDoesNotSignOutDirectly() async {
        await signIn()
        // HER-237's interceptor is what fires the sign-out. This call only
        // needs to swallow the propagated error without crashing.
        mock.getMeResult = .failure(APIError.unauthorized)

        await state.refreshCurrentUserIfNeeded(authClient: mock, now: Date(timeIntervalSince1970: 1_000))

        XCTAssertNil(state.lastMeFetchAt)
        // We don't assert isAuthenticated here because the interceptor (not
        // this method) is responsible for that side effect.
    }

    func testAuthSuccessRestoresUserScopedActiveVault() async {
        let vaultID = UUID()
        await state.activeVaultStore.select(vaultID, for: signedInUserId)

        await signIn()

        let restored = await state.activeVaultStore.selectedVaultID()
        XCTAssertEqual(restored, vaultID)
    }

    func testRefreshRestoresActiveVaultWhenStoredSessionLearnsUserID() async {
        let vaultID = UUID()
        await state.activeVaultStore.select(vaultID, for: signedInUserId)
        state = AppState(keychain: KeychainService(service: "test.her238.cold.\(UUID().uuidString)"))
        state.keychain.accessToken = "stored-access"
        state.isAuthenticated = true

        await state.refreshCurrentUserIfNeeded(authClient: mock, now: Date(timeIntervalSince1970: 1_000))

        let restored = await state.activeVaultStore.selectedVaultID()
        XCTAssertEqual(restored, vaultID)
    }

    func testSignOutClearsCachedActiveVaultHeader() async {
        await signIn()
        await state.activeVaultStore.select(UUID(), for: signedInUserId)

        await state.signOut()

        let selected = await state.activeVaultStore.selectedVaultID()
        XCTAssertNil(selected)
    }

    private func signIn() async {
        // Put state into a signed-in baseline matching the stub user.
        await state.handleAuthSuccess(.stub)
    }
}
