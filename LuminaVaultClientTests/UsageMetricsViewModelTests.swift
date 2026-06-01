// LuminaVaultClient/LuminaVaultClientTests/UsageMetricsViewModelTests.swift

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class UsageMetricsViewModelTests: XCTestCase {
    func testRefreshLoadsUsageFromBillingClient() async {
        let client = MockBillingClient()
        client.usageResult = .success(Self.usage(
            storageBytes: 1_572_864,
            tokensIn: 120,
            tokensOut: 80,
            ttsCharacters: 350,
            compileRuns: 2,
            compileFiles: 7
        ))

        let viewModel = UsageMetricsViewModel(client: client)
        await viewModel.refresh()

        XCTAssertEqual(client.usageFetchCalls, 1)
        XCTAssertEqual(viewModel.storageLabel, "1.6 MB")
        XCTAssertEqual(viewModel.tokensLabel, "200")
        XCTAssertEqual(viewModel.compilesLabel, "2")
        XCTAssertEqual(viewModel.compileFilesLabel, "7 files")
        XCTAssertEqual(viewModel.ttsCharactersLabel, "350")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRefreshFailureKeepsPriorUsageAndRecordsError() async {
        let client = MockBillingClient()
        client.usageResult = .success(Self.usage(storageBytes: 2048, tokensIn: 1, tokensOut: 2))

        let viewModel = UsageMetricsViewModel(client: client)
        await viewModel.refresh()
        XCTAssertEqual(viewModel.storageLabel, "2 KB")

        client.usageResult = .failure(NSError(domain: "net", code: -1))
        await viewModel.refresh()

        XCTAssertEqual(viewModel.storageLabel, "2 KB")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    private static func usage(
        storageBytes: Int64,
        tokensIn: Int64,
        tokensOut: Int64,
        ttsCharacters: Int64 = 0,
        compileRuns: Int64 = 0,
        compileFiles: Int64 = 0
    ) -> MeUsageResponse {
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        return MeUsageResponse(
            tier: .trial,
            periodStart: start,
            periodEnd: start.addingTimeInterval(31 * 86_400),
            generatedAt: start,
            storageBytes: storageBytes,
            tokensIn: tokensIn,
            tokensOut: tokensOut,
            tokensTotal: tokensIn + tokensOut,
            ttsCharacters: ttsCharacters,
            compileRuns: compileRuns,
            compileFiles: compileFiles,
            daily: []
        )
    }
}
