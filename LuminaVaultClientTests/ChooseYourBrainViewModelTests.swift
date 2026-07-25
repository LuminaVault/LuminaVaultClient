// LuminaVaultClient/LuminaVaultClientTests/ChooseYourBrainViewModelTests.swift
//
// HER-300 ticket 4 — verifies the Choose-Your-Brain view model PUTs the
// managed-default LLM preference, latches the onboarding step on either
// path, and advances even when network calls soft-fail.

@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class ChooseYourBrainViewModelTests: XCTestCase {
    // MARK: Test doubles

    private final class MockLLMPreferencesClient: LLMPreferencesClientProtocol {
        var stubbedGet: LLMPreferencesGetResponse = .init(
            mode: .managed,
            primaryProvider: .openRouter,
            primaryModel: "deepseek/deepseek-v4-flash",
            fallbackChain: []
        )
        var stubbedPutResponse: LLMPreferencesGetResponse?
        var putError: Error?
        private(set) var putCalls: [LLMPreferencesPutRequest] = []

        func get() async throws -> LLMPreferencesGetResponse {
            stubbedGet
        }

        func put(_ body: LLMPreferencesPutRequest) async throws -> LLMPreferencesGetResponse {
            putCalls.append(body)
            if let putError {
                throw putError
            }
            return stubbedPutResponse ?? stubbedGet
        }
    }

    private final class MockOnboardingClient: OnboardingClientProtocol {
        var stubbedState: OnboardingStateDTO = .init(
            signupCompleted: true,
            signupCompletedAt: nil,
            emailVerifiedCompleted: true,
            emailVerifiedCompletedAt: nil,
            soulConfiguredCompleted: true,
            soulConfiguredCompletedAt: nil,
            firstCaptureCompleted: false,
            firstCaptureCompletedAt: nil,
            firstKBCompileCompleted: false,
            firstKBCompileCompletedAt: nil,
            firstQueryCompleted: false,
            firstQueryCompletedAt: nil,
            brainConfiguredCompleted: false,
            brainConfiguredCompletedAt: nil
        )
        var patchError: Error?
        private(set) var patchCalls: [OnboardingPatchRequest] = []

        func get() async throws -> OnboardingStateDTO {
            stubbedState
        }

        func patch(_ body: OnboardingPatchRequest) async throws -> OnboardingStateDTO {
            patchCalls.append(body)
            if let patchError {
                throw patchError
            }
            return stubbedState
        }
    }

    private struct DummyError: LocalizedError {
        let errorDescription: String? = "network down"
    }

    // MARK: Fixtures

    private var preferencesClient: MockLLMPreferencesClient!
    private var onboardingClient: MockOnboardingClient!
    private var completedCount: Int = 0

    override func setUp() async throws {
        try await super.setUp()
        preferencesClient = MockLLMPreferencesClient()
        onboardingClient = MockOnboardingClient()
        completedCount = 0
    }

    private func makeSUT() -> ChooseYourBrainViewModel {
        ChooseYourBrainViewModel(
            preferencesClient: preferencesClient,
            onboardingClient: onboardingClient,
            onCompleted: { [self] in completedCount += 1 }
        )
    }

    private func waitForBYOKPatch(_ sut: ChooseYourBrainViewModel) async {
        for _ in 0 ..< 200 {
            if sut.shouldNavigateToProviders || sut.errorMessage != nil {
                return
            }
            await Task.yield()
        }
    }

    // MARK: Managed-default path

    func testAcceptManagedDefaultPutsCorrectPayloadAndPatchesFlag() async throws {
        let sut = makeSUT()
        await sut.performAcceptManagedDefault()

        XCTAssertEqual(preferencesClient.putCalls.count, 1)
        let put = try XCTUnwrap(preferencesClient.putCalls.first)
        XCTAssertEqual(put.mode, .managed)
        XCTAssertEqual(put.primaryProvider, .custom)
        XCTAssertEqual(put.primaryModel, "")
        XCTAssertTrue(put.fallbackChain.isEmpty)

        XCTAssertEqual(onboardingClient.patchCalls.count, 1)
        XCTAssertEqual(onboardingClient.patchCalls.first?.brainConfiguredCompleted, true)

        XCTAssertEqual(completedCount, 1)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isSubmitting)
        XCTAssertFalse(sut.shouldNavigateToProviders)
    }

    func testAcceptManagedDefaultPutFailureStillCompletesAndStillPatches() async {
        preferencesClient.putError = DummyError()
        let sut = makeSUT()
        await sut.performAcceptManagedDefault()

        XCTAssertEqual(preferencesClient.putCalls.count, 1)
        XCTAssertEqual(onboardingClient.patchCalls.count, 1)
        XCTAssertEqual(completedCount, 1)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isSubmitting)
    }

    func testAcceptManagedDefaultPatchFailureStillCompletes() async {
        onboardingClient.patchError = DummyError()
        let sut = makeSUT()
        await sut.performAcceptManagedDefault()

        XCTAssertEqual(preferencesClient.putCalls.count, 1)
        XCTAssertEqual(onboardingClient.patchCalls.count, 1)
        XCTAssertEqual(completedCount, 1)
        XCTAssertNil(sut.errorMessage)
    }

    func testAcceptManagedDefaultCancellationStillCompletes() async {
        onboardingClient.patchError = CancellationError()
        let sut = makeSUT()
        await sut.performAcceptManagedDefault()

        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(completedCount, 1)
    }

    func testAcceptManagedDefaultURLErrorCancelledStillCompletes() async {
        onboardingClient.patchError = URLError(.cancelled)
        let sut = makeSUT()
        await sut.performAcceptManagedDefault()

        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(completedCount, 1)
    }

    // MARK: BYOK path

    func testSelectBYOKPatchesFlagAndFlipsNavigationWithoutCompleting() async {
        let sut = makeSUT()
        await sut.performSelectBYOK()

        XCTAssertTrue(preferencesClient.putCalls.isEmpty,
                      "BYOK path must not PUT — preferences are written when the user saves their first key.")
        XCTAssertEqual(onboardingClient.patchCalls.count, 1)
        XCTAssertEqual(onboardingClient.patchCalls.first?.brainConfiguredCompleted, true)
        XCTAssertTrue(sut.shouldNavigateToProviders)
        XCTAssertEqual(completedCount, 0)
        XCTAssertNil(sut.errorMessage)
    }

    func testFinishBYOKNavigationInvokesOnCompleted() {
        let sut = makeSUT()
        sut.finishBYOKNavigation()
        XCTAssertEqual(completedCount, 1)
    }

    func testSelectBYOKPatchFailureStillNavigates() async {
        onboardingClient.patchError = DummyError()
        let sut = makeSUT()
        await sut.performSelectBYOK()

        XCTAssertEqual(onboardingClient.patchCalls.count, 1)
        XCTAssertTrue(sut.shouldNavigateToProviders)
        XCTAssertEqual(completedCount, 0)
        XCTAssertNil(sut.errorMessage)
    }

    func testSelectBYOKCancellationStillNavigates() async {
        onboardingClient.patchError = CancellationError()
        let sut = makeSUT()
        await sut.performSelectBYOK()

        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(sut.shouldNavigateToProviders)
        XCTAssertEqual(completedCount, 0)
    }

    func testSelectBYOKNetworkFailureCancelledStillNavigates() async {
        onboardingClient.patchError = APIError.networkFailure(URLError(.cancelled))
        let sut = makeSUT()
        await sut.performSelectBYOK()

        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(sut.shouldNavigateToProviders)
        XCTAssertEqual(completedCount, 0)
    }

    // MARK: Concurrent-tap safety

    func testInFlightSubmitBlocksReentrantCalls() async {
        let sut = makeSUT()
        await sut.performAcceptManagedDefault()
        XCTAssertFalse(sut.isSubmitting)
        XCTAssertEqual(preferencesClient.putCalls.count, 1)
    }

    func testPublicEntryPointsRunWorkToCompletion() async {
        let sut = makeSUT()
        sut.selectBYOK()
        await waitForBYOKPatch(sut)

        XCTAssertEqual(onboardingClient.patchCalls.count, 1)
        XCTAssertTrue(sut.shouldNavigateToProviders)
        XCTAssertEqual(completedCount, 0)
    }
}
