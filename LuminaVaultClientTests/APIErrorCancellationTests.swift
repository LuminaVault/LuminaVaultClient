// LuminaVaultClient/LuminaVaultClientTests/APIErrorCancellationTests.swift

@testable import LuminaVaultClient
import XCTest

final class APIErrorCancellationTests: XCTestCase {
    /// `isBenignCancellation` now consults `PinningFailureLog`, so a rejection
    /// recorded by another test would make these cancels look like TLS
    /// failures. Clear it so the suite stays order-independent.
    override func setUp() {
        super.setUp()
        PinningFailureLog.reset()
    }

    func testCancellationErrorIsBenign() {
        XCTAssertTrue(APIError.isBenignCancellation(CancellationError()))
    }

    func testURLErrorCancelledIsBenign() {
        XCTAssertTrue(APIError.isBenignCancellation(URLError(.cancelled)))
    }

    func testWrappedNetworkFailureCancelledIsBenign() {
        let wrapped = APIError.networkFailure(URLError(.cancelled))
        XCTAssertTrue(APIError.isBenignCancellation(wrapped))
        XCTAssertTrue(wrapped.isBenignCancellation)
    }

    func testRealNetworkFailureIsNotBenign() {
        let wrapped = APIError.networkFailure(URLError(.timedOut))
        XCTAssertFalse(APIError.isBenignCancellation(wrapped))
    }
}
