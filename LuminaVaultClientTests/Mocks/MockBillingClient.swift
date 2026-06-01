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
    var usageResult: Result<MeUsageResponse, Error> = .success(
        MeUsageResponse(
            tier: .trial,
            periodStart: Date(timeIntervalSince1970: 1_767_225_600),
            periodEnd: Date(timeIntervalSince1970: 1_769_904_000),
            generatedAt: Date(timeIntervalSince1970: 1_767_225_600),
            storageBytes: 0,
            tokensIn: 0,
            tokensOut: 0,
            tokensTotal: 0,
            ttsCharacters: 0,
            compileRuns: 0,
            compileFiles: 0,
            daily: []
        )
    )
    private(set) var usageFetchCalls = 0

    func fetchMeBilling() async throws -> MeBillingResponse {
        fetchCalls += 1
        return try fetchResult.get()
    }

    func fetchMeUsage() async throws -> MeUsageResponse {
        usageFetchCalls += 1
        return try usageResult.get()
    }
}
