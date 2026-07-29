import XCTest
@testable import LuminaVaultClient

final class ActiveVaultStoreTests: XCTestCase {
    func testRestoreUsesAuthenticatedUserScope() async {
        let userA = UUID()
        let userB = UUID()
        let vaultA = UUID()
        let vaultB = UUID()
        defer {
            UserDefaults.standard.removeObject(forKey: "lv.active-vault.\(userA.uuidString)")
            UserDefaults.standard.removeObject(forKey: "lv.active-vault.\(userB.uuidString)")
        }

        let store = ActiveVaultStore()
        await store.select(vaultA, for: userA)
        await store.select(vaultB, for: userB)

        await store.restore(for: userA)
        let restoredA = await store.selectedVaultID()
        XCTAssertEqual(restoredA, vaultA)

        await store.restore(for: userB)
        let restoredB = await store.selectedVaultID()
        XCTAssertEqual(restoredB, vaultB)
    }

    func testAnonymousSelectionIsNotPersistedOrRestored() async {
        let anonymousKey = "lv.active-vault.anonymous"
        UserDefaults.standard.removeObject(forKey: anonymousKey)
        defer { UserDefaults.standard.removeObject(forKey: anonymousKey) }

        let store = ActiveVaultStore()
        await store.select(UUID(), for: nil)

        XCTAssertNil(UserDefaults.standard.string(forKey: anonymousKey))

        await store.restore(for: nil)
        let restored = await store.selectedVaultID()
        XCTAssertNil(restored)
    }
}
