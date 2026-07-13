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

    func testQualityHonorsDisabledLocalFallback() {
        let decision = HybridExecutionCoordinator().decide(
            profile: .quality,
            capabilities: .init(
                localAvailable: true,
                cloudAvailable: false,
                requiresCloudTool: false,
                contextFitsLocally: true,
                localFallbackEnabled: false
            )
        )
        XCTAssertEqual(decision, .unavailable("Cloud is unavailable and local fallback cannot handle this turn."))
    }

    func testBalancedHonorsDisabledCloudFallback() {
        let decision = HybridExecutionCoordinator().decide(
            profile: .balanced,
            capabilities: .init(
                localAvailable: false,
                cloudAvailable: true,
                requiresCloudTool: false,
                contextFitsLocally: true,
                cloudFallbackEnabled: false
            )
        )
        XCTAssertEqual(decision, .unavailable("The local model cannot handle this turn and cloud fallback is unavailable."))
    }

    @MainActor
    func testSettingsKeepEndpointSecretInKeychain() throws {
        let suiteName = "HybridExecutionCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = KeychainService(inMemory: true)
        let settings = HybridExecutionSettingsStore(defaults: defaults, keychain: keychain)
        settings.profile = .private
        settings.apiKey = "device-secret"
        settings.useAppleOnDeviceModel = true
        settings.localFallbackEnabled = false
        settings.cloudFallbackEnabled = false
        settings.syncLocalConversations = false

        settings.save(defaults: defaults, keychain: keychain)

        XCTAssertEqual(defaults.string(forKey: "hybrid.profile"), HybridExecutionProfile.private.rawValue)
        XCTAssertNil(defaults.string(forKey: "localEndpointAPIKey"))
        XCTAssertEqual(keychain.localEndpointAPIKey, "device-secret")
        XCTAssertTrue(defaults.bool(forKey: "hybrid.useAppleOnDeviceModel"))
        XCTAssertFalse(defaults.bool(forKey: "hybrid.localFallbackEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "hybrid.cloudFallbackEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "hybrid.syncLocalConversations"))
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
