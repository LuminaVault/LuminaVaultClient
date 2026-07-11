@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

final class HybridExecutionCoordinatorTests: XCTestCase {
    func testPrivateNeverRoutesToCloud() {
        let decision = HybridExecutionCoordinator().decide(
            profile: .private,
            capabilities: .init(localAvailable: false, cloudAvailable: true, requiresCloudTool: false, contextFitsLocally: true)
        )
        XCTAssertEqual(decision, .unavailable("Private mode needs a downloaded model or reachable local endpoint."))
    }

    func testBalancedPrefersEligibleLocalModel() {
        let decision = HybridExecutionCoordinator().decide(
            profile: .balanced,
            capabilities: .init(localAvailable: true, cloudAvailable: true, requiresCloudTool: false, contextFitsLocally: true)
        )
        XCTAssertEqual(decision, .local)
    }

    func testQualityFallsBackLocallyWhenCloudIsOffline() {
        let decision = HybridExecutionCoordinator().decide(
            profile: .quality,
            capabilities: .init(localAvailable: true, cloudAvailable: false, requiresCloudTool: false, contextFitsLocally: true)
        )
        XCTAssertEqual(decision, .local)
    }

    @MainActor
    func testSettingsKeepEndpointSecretInKeychain() {
        let suiteName = "HybridExecutionCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = KeychainService(inMemory: true)
        let settings = HybridExecutionSettingsStore(defaults: defaults, keychain: keychain)
        settings.profile = .private
        settings.apiKey = "device-secret"
        settings.useAppleOnDeviceModel = true

        settings.save(defaults: defaults, keychain: keychain)

        XCTAssertEqual(defaults.string(forKey: "hybrid.profile"), HybridExecutionProfile.private.rawValue)
        XCTAssertNil(defaults.string(forKey: "localEndpointAPIKey"))
        XCTAssertEqual(keychain.localEndpointAPIKey, "device-secret")
        XCTAssertTrue(defaults.bool(forKey: "hybrid.useAppleOnDeviceModel"))
    }

    func testEncryptedMemoryCacheMergesUpdatesAndTombstones() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "memories.cache")
        let cache = EncryptedLocalMemoryCache(fileURL: fileURL, keyData: Data(repeating: 7, count: 32))
        let id = UUID()
        let now = Date.now
        let original = LocalMemorySyncItemDTO(id: id, content: "first", source: .legacy, createdAt: now, updatedAt: now)
        let updated = LocalMemorySyncItemDTO(id: id, content: "second", source: .legacy, createdAt: now, updatedAt: now.addingTimeInterval(1))

        try await cache.merge(.init(memories: [original]))
        try await cache.merge(.init(memories: [updated]))
        let updatedValues = try await cache.load()
        XCTAssertEqual(updatedValues.map(\.content), ["second"])

        try await cache.merge(.init(memories: [], deletedIDs: [id]))
        let deletedValues = try await cache.load()
        XCTAssertTrue(deletedValues.isEmpty)
    }
}
