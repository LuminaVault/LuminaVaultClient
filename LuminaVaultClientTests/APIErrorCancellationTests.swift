// LuminaVaultClient/LuminaVaultClientTests/APIErrorCancellationTests.swift

@testable import LuminaVaultClient
import XCTest

final class APIErrorCancellationTests: XCTestCase {
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
