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
}
