// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockBillingClient.swift
// HER-185 — scripted BillingClientProtocol fake.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

final class MockBillingClient: BillingClientProtocol, @unchecked Sendable {
    var fetchResult: Result<MeBillingResponse, Error> = .success(
        MeBillingResponse(
            tier: .trial,
            tierOverride: nil,
            inTrial: true,
            daysRemaining: 14,
            enforcementEnabled: true
        )
    )
    private(set) var fetchCalls = 0

    func fetchMeBilling() async throws -> MeBillingResponse {
        fetchCalls += 1
        return try fetchResult.get()
    }
}
