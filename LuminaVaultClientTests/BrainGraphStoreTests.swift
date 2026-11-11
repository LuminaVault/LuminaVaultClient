// Port of the web app's brain-graph-view-model.test.ts, case by case, plus the
// iOS-only cases (SwiftUI cancellation, error predicates, truncatedCount).
// Time never passes for real: the debounce runs on `TestSleeper`.

import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

@MainActor
struct BrainGraphStoreTests {
    // MARK: fixtures

    private static func vaultID(_ n: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, n))
    }

    private static let v0 = vaultID(0)
    private static let v1 = vaultID(1)
    private static let v2 = vaultID(2)
    private static let v9 = vaultID(9)

    private static func node(_ id: String, _ kind: BrainNodeKindDTO) -> BrainGraphNodeDTO {
        BrainGraphNodeDTO(id: id, kind: kind, label: id, weight: 0)
    }

    /// Responses are told apart by `generatedAt`.
    private static func response(
        at seconds: TimeInterval, truncated: Bool = false,
        vaults: [BrainGraphVaultDTO]? = nil, nodes: [BrainGraphNodeDTO] = []
    ) -> BrainGraphResponse {
        BrainGraphResponse(
            generatedAt: Date(timeIntervalSince1970: seconds), truncated: truncated,
            vaults: vaults ?? [BrainGraphVaultDTO(id: v1, name: "Personal", personal: true)],
            nodes: nodes, edges: []
        )
    }

    private static let graph = response(at: 1, nodes: [node("N1", .note)])
    private static let other = response(at: 2)
    private static let all = BrainGraphRequest()
    private static let focused = BrainGraphRequest(focus: "ABC")

    private func stamp(_ store: BrainGraphStore) -> TimeInterval? {
        if case .loaded(let g) = store.state { return g.generatedAt.timeIntervalSince1970 }
        return nil
    }

    private func isLoading(_ state: BrainGraphLoadState) -> Bool {
        if case .loading = state { return true }
        return false
    }

    private func isMissingFocus(_ state: BrainGraphLoadState) -> Bool {
        if case .missingFocus = state { return true }
        return false
    }

    private func failedMessage(_ state: BrainGraphLoadState) -> String? {
        if case .failed(let m) = state { return m }
        return nil
    }

    private struct Rig {
        let mock: MockBrainGraphClient
        let sleeper: TestSleeper
        let store: BrainGraphStore
    }

    private func rig(_ results: [Result<BrainGraphResponse, Error>] = []) -> Rig {
        let mock = MockBrainGraphClient(results: results)
        let sleeper = TestSleeper()
        let store = BrainGraphStore(client: mock, sleep: sleeper.sleep)
        return Rig(mock: mock, sleeper: sleeper, store: store)
    }

    /// `sync(all)` answered with `graph`, ready for the debounce cases.
    private func shown() async -> Rig {
        let r = rig()
        await r.mock.enqueueOnce(.success(Self.graph))
        r.store.sync(Self.all)
        await r.store.waitUntilIdle()
        return r
    }

    // MARK: load

    @Test func startsLoadingAndEndsLoadedAfterASuccessfulLoad() async {
        let r = rig([.success(Self.graph)])
        #expect(isLoading(r.store.state))
        await r.store.load(Self.all)
        #expect(stamp(r.store) == 1)
        #expect(!r.store.refreshing)
        #expect(r.store.request == Self.all)
        #expect(await r.mock.lastRequest?.query
            == "/v1/brain/graph?links=link%2Csource%2Ctag%2Cauthor%2Centity%2Cspace&limit=800")
    }

    @Test func keepsTheGraphSetsRateLimitedAndAsksOnceOn429() async {
        let r = rig()
        await r.mock.enqueueOnce(.success(Self.graph))
        await r.store.load(Self.all)
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.rateLimited(retryAfter: 30)))
        await r.store.load(BrainGraphRequest(similar: true))
        #expect(stamp(r.store) == 1)
        #expect(r.store.rateLimited)
        #expect(!r.store.refreshing)
        #expect(await r.mock.callCount == 2)
    }

    @Test func clearsRateLimitedOnTheNextSuccess() async {
        let r = rig()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.rateLimited()))
        await r.store.load(Self.all)
        #expect(r.store.rateLimited)
        await r.mock.enqueueOnce(.success(Self.graph))
        await r.store.load(Self.all)
        #expect(!r.store.rateLimited)
        #expect(stamp(r.store) == 1)
    }

    @Test func failsWithAFriendlyMessageOn429WhenNoGraphIsShown() async {
        let r = rig()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.rateLimited()))
        await r.store.load(Self.all)
        #expect(failedMessage(r.store.state)?.isEmpty == false)
        #expect(r.store.rateLimited)
        #expect(await r.mock.callCount == 1)
    }

    @Test func a429WrappedInAnHTTPErrorCountsAsRateLimitedToo() async {
        // BaseHTTPClient throws .httpError(429) when the body is a structured envelope.
        let r = rig()
        await r.mock.enqueueOnce(.success(Self.graph))
        await r.store.load(Self.all)
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(429)))
        await r.store.load(Self.focused)
        #expect(r.store.rateLimited)
        #expect(stamp(r.store) == 1)
    }

    @Test func keepsTheGraphAndSetsRefreshErrorWhenARefetchFails() async {
        let r = rig()
        await r.mock.enqueueOnce(.success(Self.graph))
        await r.store.load(Self.all)
        #expect(r.store.refreshError == nil)
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(500)))
        await r.store.load(BrainGraphRequest(similar: true))
        #expect(stamp(r.store) == 1)
        #expect(r.store.refreshError?.isEmpty == false)
        #expect(!r.store.refreshing)
        #expect(!r.store.rateLimited)
        await r.mock.enqueueOnce(.success(Self.other))
        await r.store.load(Self.all)
        #expect(r.store.refreshError == nil)
        #expect(stamp(r.store) == 2)
    }

    @Test func stillFailsAFirstLoadThatErrorsWithoutARefreshError() async {
        let r = rig()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(500)))
        await r.store.load(Self.all)
        #expect(failedMessage(r.store.state) != nil)
        #expect(r.store.refreshError == nil)
    }

    @Test func reportsMissingFocusOn404WithAFocusEvenOverAShownGraph() async {
        let r = rig()
        await r.mock.enqueueOnce(.success(Self.graph))
        await r.store.load(Self.all)
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(404)))
        await r.store.load(Self.focused)
        #expect(isMissingFocus(r.store.state))
        #expect(r.store.refreshError == nil)
    }

    @Test func reportsMissingFocusOn404WithAFocus() async {
        let r = rig()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(404)))
        await r.store.load(Self.focused)
        #expect(isMissingFocus(r.store.state))
    }

    @Test func failsOn404WithoutAFocus() async {
        let r = rig()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(404)))
        await r.store.load(Self.all)
        #expect(failedMessage(r.store.state) != nil)
    }

    @Test func flagsRefreshingWhileARefetchRunsOverAShownGraph() async {
        let r = rig()
        await r.mock.enqueueOnce(.success(Self.graph))
        await r.store.load(Self.all)
        let held = await r.mock.enqueueHeld()
        let pending = r.store.startLoad(Self.focused)
        #expect(r.store.refreshing)
        #expect(stamp(r.store) == 1)
        held.release(Self.other)
        await pending.value
        #expect(!r.store.refreshing)
        #expect(stamp(r.store) == 2)
    }

    @Test func coalescesThreeScheduleCallsInside400msIntoOneRequest() async {
        let r = rig([.success(Self.graph)])
        r.store.schedule(BrainGraphRequest(depth: 1))
        await r.sleeper.waitForRegistrations(1)
        r.sleeper.advance(by: .milliseconds(100))
        r.store.schedule(BrainGraphRequest(depth: 2))
        await r.sleeper.waitForRegistrations(2)
        r.sleeper.advance(by: .milliseconds(100))
        r.store.schedule(BrainGraphRequest(focus: "ABC", depth: 3))
        await r.sleeper.waitForRegistrations(3)
        #expect(await r.mock.callCount == 0)
        r.sleeper.advance(by: .milliseconds(400))
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 1)
        #expect(await r.mock.lastRequest?.query.contains("focus=ABC&depth=3") == true)
        #expect(r.store.request == BrainGraphRequest(focus: "ABC", depth: 3))
    }

    @Test func remembersTheRequestBehindTheGraphOnScreenNotOneThatFailed() async {
        let r = rig()
        await r.mock.enqueueOnce(.success(Self.graph))
        #expect(r.store.loaded == nil)
        await r.store.load(Self.all)
        #expect(r.store.loaded == Self.all)
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.rateLimited()))
        await r.store.load(BrainGraphRequest(similar: true))
        #expect(r.store.request == BrainGraphRequest(similar: true))
        #expect(r.store.loaded == Self.all)
    }

    @Test func cancelDropsAScheduledLoad() async {
        let r = rig([.success(Self.graph)])
        r.store.schedule(Self.all)
        await r.sleeper.waitForRegistrations(1)
        r.store.cancel()
        r.sleeper.advance(by: .seconds(1))
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 0)
    }

    @Test func disposeCancelsAPendingDebounce() async {
        let r = rig([.success(Self.graph)])
        r.store.schedule(Self.all)
        await r.sleeper.waitForRegistrations(1)
        r.store.dispose()
        r.sleeper.advance(by: .seconds(1))
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 0)
    }

    @Test func ignoresAResponseThatArrivesAfterANewerRequestStarted() async {
        let r = rig()
        // This transport does not notice cancellation, so the old answer really arrives.
        let first = await r.mock.enqueueHeld(honoursCancellation: false)
        await r.mock.enqueueOnce(.success(Self.other))
        let firstTask = r.store.startLoad(Self.all)
        await r.mock.waitForCalls(1)
        await r.store.load(Self.focused)
        #expect(stamp(r.store) == 2)
        first.release(Self.graph)
        await firstTask.value
        #expect(stamp(r.store) == 2)
        #expect(r.store.request == Self.focused)
    }

    @Test func cancelsASupersededRequest() async {
        let r = rig()
        let first = await r.mock.enqueueHeld()
        let second = await r.mock.enqueueHeld()
        let firstTask = r.store.startLoad(Self.all)
        await r.mock.waitForCalls(1)
        let secondTask = r.store.startLoad(Self.focused)
        await r.mock.waitForCalls(2)
        await firstTask.value
        #expect(first.wasCancelled)
        #expect(!second.wasCancelled)
        second.release(Self.graph)
        await secondTask.value
        #expect(stamp(r.store) == 1)
    }

    @Test func keepsTheHTTPStatusOfAFailedLoad() async {
        let r = rig()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(403)))
        await r.store.load(BrainGraphRequest(vaults: [Self.v9]))
        #expect(failedMessage(r.store.state) != nil)
        #expect(r.store.failureStatus == 403)
    }

    @Test func clearsRateLimitedAfterALaterRequestThatFailsWithSomethingElse() async {
        let r = rig()
        await r.mock.enqueueOnce(.success(Self.graph))
        await r.store.load(Self.all)
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.rateLimited()))
        await r.store.load(Self.focused)
        #expect(r.store.rateLimited)
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(500)))
        await r.store.load(BrainGraphRequest(similar: true))
        #expect(!r.store.rateLimited)
        #expect(r.store.refreshError?.isEmpty == false)
    }

    @Test func loadCancelsAPendingSchedule() async {
        let r = rig([.success(Self.graph)])
        r.store.schedule(Self.focused)
        await r.sleeper.waitForRegistrations(1)
        await r.store.load(Self.all)
        r.sleeper.advance(by: .seconds(1))
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 1)
        #expect(r.store.loaded == Self.all)
    }

    @Test func aSupersedingLoadKeepsRefreshingTrueUntilTheNewestLands() async {
        let r = rig()
        await r.mock.enqueueOnce(.success(Self.graph))
        await r.store.load(Self.all)
        // Both transports ignore cancellation: B's answer arrives but is stale.
        let heldB = await r.mock.enqueueHeld(honoursCancellation: false)
        let heldC = await r.mock.enqueueHeld(honoursCancellation: false)
        let b = r.store.startLoad(Self.focused)
        await r.mock.waitForCalls(2)
        let c = r.store.startLoad(BrainGraphRequest(similar: true))
        await r.mock.waitForCalls(3)
        heldB.release(Self.other)
        await b.value
        #expect(r.store.refreshing)
        #expect(stamp(r.store) == 1)
        heldC.release(Self.other)
        await c.value
        #expect(!r.store.refreshing)
        #expect(r.store.loaded == BrainGraphRequest(similar: true))
    }

    @Test func disposeCancelsAnInFlightRequestThatHonoursCancellation() async {
        let r = rig()
        let held = await r.mock.enqueueHeld(honoursCancellation: true)
        let pending = r.store.startLoad(Self.all)
        await r.mock.waitForCalls(1)
        r.store.dispose()
        await pending.value
        #expect(held.wasCancelled)
        #expect(isLoading(r.store.state))
        #expect(r.store.loaded == nil)
    }

    @Test func disposeDropsAResponseThatIsInFlight() async {
        let r = rig()
        let held = await r.mock.enqueueHeld(honoursCancellation: false)
        let pending = r.store.startLoad(Self.all)
        await r.mock.waitForCalls(1)
        r.store.dispose()
        held.release(Self.graph)
        await pending.value
        #expect(isLoading(r.store.state))
        #expect(r.store.loaded == nil)
        #expect(r.store.knownVaults.isEmpty)
    }

    // MARK: sync

    @Test func syncLoadsTheFirstRequestAtOnce() async {
        let r = rig([.success(Self.graph)])
        r.store.sync(Self.all)
        await r.mock.waitForCalls(1)
        #expect(r.sleeper.registrations == 0)
        await r.store.waitUntilIdle()
        #expect(stamp(r.store) == 1)
    }

    @Test func syncDebouncesEveryLaterRequestBy400ms() async {
        let r = await shown()
        await r.mock.enqueueOnce(.success(Self.other))
        r.store.sync(Self.focused)
        await r.sleeper.waitForRegistrations(1)
        #expect(r.sleeper.requestedDurations == [.milliseconds(400)])
        r.sleeper.advance(by: .milliseconds(399))
        await Task.yield()
        #expect(await r.mock.callCount == 1)
        #expect(r.sleeper.activeCount == 1)
        #expect(r.store.pending)
        r.sleeper.advance(by: .milliseconds(1))
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 2)
        #expect(r.store.loaded == Self.focused)
    }

    @Test func goingBackToTheGraphOnScreenCancelsThePendingRequestAndAsksNothing() async {
        let r = await shown()
        r.store.sync(Self.focused)
        await r.sleeper.waitForRegistrations(1)
        r.sleeper.advance(by: .milliseconds(100))
        r.store.sync(BrainGraphRequest())
        r.sleeper.advance(by: .seconds(1))
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 1)
        #expect(!r.store.stale)
    }

    @Test func fetchesTheFullGraphAgainAfterAFocus404OverIt() async {
        let r = await shown()
        #expect(stamp(r.store) == 1)
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(404)))
        r.store.sync(Self.focused)
        await r.sleeper.waitForRegistrations(1)
        r.sleeper.advance(by: .milliseconds(400))
        await r.store.waitUntilIdle()
        #expect(isMissingFocus(r.store.state))
        await r.mock.enqueueOnce(.success(Self.other))
        r.store.sync(Self.all)
        await r.sleeper.waitForRegistrations(2)
        r.sleeper.advance(by: .milliseconds(400))
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 3)
        #expect(stamp(r.store) == 2)
        #expect(r.store.loaded == Self.all)
    }

    @Test func fetchesTheSameRequestAgainAfterAFailedFirstLoad() async {
        let r = rig()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(500)))
        r.store.sync(Self.all)
        await r.store.waitUntilIdle()
        #expect(failedMessage(r.store.state) != nil)
        await r.mock.enqueueOnce(.success(Self.graph))
        r.store.sync(BrainGraphRequest())
        await r.sleeper.waitForRegistrations(1)
        r.sleeper.advance(by: .milliseconds(400))
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 2)
        #expect(stamp(r.store) == 1)
    }

    @Test func syncOfTheRequestAlreadyLoadingSchedulesNothing() async {
        let r = rig()
        let held = await r.mock.enqueueHeld()
        r.store.sync(Self.all)
        await r.mock.waitForCalls(1)
        r.store.sync(BrainGraphRequest())
        #expect(r.sleeper.registrations == 0)
        #expect(!r.store.pending)
        held.release(Self.graph)
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 1)
        #expect(stamp(r.store) == 1)
    }

    @Test func syncOfTheRefreshAlreadyOnItsWayDropsAPendingTimerAndAsksNothing() async {
        let r = await shown()
        let held = await r.mock.enqueueHeld()
        r.store.sync(Self.focused)
        await r.sleeper.waitForRegistrations(1)
        r.sleeper.advance(by: .milliseconds(400))
        await r.mock.waitForCalls(2)
        // The tab reappears while the refresh runs: a stray scheduled request for
        // something else must go, and the same request must not be re-sent.
        r.store.sync(BrainGraphRequest(similar: true))
        #expect(r.store.pending)
        r.store.sync(Self.focused)
        #expect(!r.store.pending)
        r.sleeper.advance(by: .seconds(1))
        held.release(Self.other)
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 2)
        #expect(r.store.loaded == Self.focused)
    }

    @Test func aScheduledRequestThatHasLandedMeanwhileIsNotFetchedAgain() async {
        let r = await shown()
        r.store.schedule(Self.all)
        await r.sleeper.waitForRegistrations(1)
        r.sleeper.advance(by: .milliseconds(400))
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 1)
        #expect(!r.store.pending)
        #expect(r.store.loaded == Self.all)
    }

    @Test func aTransportCancelledFirstLoadBecomesARetryableFailure() async {
        let r = rig()
        await r.mock.enqueueOnce(.failure(CancellationError()))
        r.store.sync(Self.all)
        await r.store.waitUntilIdle()
        #expect(failedMessage(r.store.state) == "The graph did not load. Try again.")
        #expect(r.store.failureStatus == nil)
        #expect(!r.store.refreshing)
        await r.mock.enqueueOnce(.success(Self.graph))
        await r.store.retry().value
        #expect(stamp(r.store) == 1)
    }

    @Test func twoRetriesBackToBackMakeOneRequest() async {
        let r = rig()
        let held = await r.mock.enqueueHeld()
        r.store.sync(Self.focused)
        await r.mock.waitForCalls(1)
        let first = r.store.retry()
        let second = r.store.retry()
        held.release(Self.graph)
        await first.value
        await second.value
        #expect(await r.mock.callCount == 1)
        #expect(stamp(r.store) == 1)
    }

    // MARK: stale

    @Test func staleIsFalseWhileNothingDiffersWhileDebouncingAndWhileRefreshing() async {
        let r = await shown()
        #expect(!r.store.stale)
        let held = await r.mock.enqueueHeld()
        r.store.sync(Self.focused)
        #expect(!r.store.stale)
        await r.sleeper.waitForRegistrations(1)
        r.sleeper.advance(by: .milliseconds(400))
        await r.mock.waitForCalls(2)
        #expect(r.store.refreshing)
        #expect(!r.store.stale)
        held.release(Self.other)
        await r.store.waitUntilIdle()
        #expect(!r.store.stale)
    }

    @Test func staleIsTrueAfterARefusedRefetchAndRetryClearsIt() async {
        let r = await shown()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.rateLimited()))
        r.store.sync(Self.focused)
        await r.sleeper.waitForRegistrations(1)
        r.sleeper.advance(by: .milliseconds(400))
        await r.store.waitUntilIdle()
        #expect(r.store.rateLimited)
        #expect(r.store.stale)
        await r.mock.enqueueOnce(.success(Self.other))
        await r.store.retry().value
        #expect(await r.mock.lastRequest?.query.contains("focus=ABC") == true)
        #expect(!r.store.stale)
        #expect(!r.store.rateLimited)
        #expect(r.store.loaded == Self.focused)
    }

    @Test func staleIsTrueAfterAFailedRefetch() async {
        let r = await shown()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(500)))
        r.store.sync(Self.focused)
        await r.sleeper.waitForRegistrations(1)
        r.sleeper.advance(by: .milliseconds(400))
        await r.store.waitUntilIdle()
        #expect(stamp(r.store) == 1)
        #expect(r.store.stale)
    }

    @Test func staleClearsWhenTheRequestGoesBackToTheGraphOnScreen() async {
        let r = await shown()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(500)))
        r.store.sync(Self.focused)
        await r.sleeper.waitForRegistrations(1)
        r.sleeper.advance(by: .milliseconds(400))
        await r.store.waitUntilIdle()
        #expect(r.store.stale)
        r.store.sync(Self.all)
        #expect(!r.store.stale)
        r.sleeper.advance(by: .seconds(1))
        await r.store.waitUntilIdle()
        #expect(await r.mock.callCount == 2)
    }

    @Test func retryLoadsTheLastRequestAfterAFailedFirstLoad() async {
        let r = rig()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(500)))
        r.store.sync(Self.focused)
        await r.store.waitUntilIdle()
        #expect(failedMessage(r.store.state) != nil)
        await r.mock.enqueueOnce(.success(Self.graph))
        await r.store.retry().value
        #expect(stamp(r.store) == 1)
        #expect(r.store.loaded == Self.focused)
    }

    // MARK: knownVaults

    private static let personal = BrainGraphVaultDTO(id: v1, name: "Personal", personal: true)
    private static let acme = BrainGraphVaultDTO(id: v2, name: "Acme", personal: false)
    private static let zeta = BrainGraphVaultDTO(id: v0, name: "Acme", personal: false)

    private func ids(_ vaults: [BrainGraphVaultDTO]) -> [UUID] { vaults.map(\.id) }

    @Test func knownVaultsIsEveryVaultOfTheFirstUnfilteredResponseSortedByNameThenID() async {
        let r = rig()
        #expect(r.store.knownVaults.isEmpty)
        await r.mock.enqueueOnce(.success(Self.response(at: 1, vaults: [Self.personal, Self.acme, Self.zeta])))
        await r.store.load(Self.all)
        #expect(ids(r.store.knownVaults) == [Self.v0, Self.v2, Self.v1])
        // A narrowed response later does not shrink it.
        await r.mock.enqueueOnce(.success(Self.response(at: 1, vaults: [Self.personal])))
        await r.store.load(BrainGraphRequest(vaults: [Self.v1]))
        #expect(ids(r.store.knownVaults) == [Self.v0, Self.v2, Self.v1])
    }

    @Test func knownVaultsIsTheUnionOfVaultsSeenUntilAnUnfilteredResponseArrives() async {
        let r = rig()
        await r.mock.enqueueOnce(.success(Self.response(at: 1, vaults: [Self.personal])))
        await r.store.load(BrainGraphRequest(vaults: [Self.v1]))
        #expect(ids(r.store.knownVaults) == [Self.v1])
        await r.mock.enqueueOnce(.success(Self.response(at: 1, vaults: [Self.acme])))
        await r.store.load(BrainGraphRequest(vaults: [Self.v2]))
        #expect(ids(r.store.knownVaults) == [Self.v2, Self.v1])
        await r.mock.enqueueOnce(.success(Self.response(at: 1, vaults: [Self.personal, Self.zeta])))
        await r.store.load(Self.all)
        #expect(ids(r.store.knownVaults) == [Self.v0, Self.v1])
    }

    @Test func knownVaultsSortsAccentedNamesAsTheWebDoes() async {
        let r = rig()
        let accented = BrainGraphVaultDTO(id: Self.v1, name: "Été", personal: false)
        let zeta = BrainGraphVaultDTO(id: Self.v2, name: "Zeta", personal: false)
        let alpha = BrainGraphVaultDTO(id: Self.v0, name: "Alpha", personal: false)
        await r.mock.enqueueOnce(.success(Self.response(at: 1, vaults: [zeta, accented, alpha])))
        await r.store.load(Self.all)
        #expect(ids(r.store.knownVaults) == [Self.v0, Self.v1, Self.v2])
    }

    @Test func knownVaultsSortsNamesWithoutRegardToCase() async {
        let r = rig()
        let lower = BrainGraphVaultDTO(id: Self.v1, name: "acme", personal: false)
        let upper = BrainGraphVaultDTO(id: Self.v2, name: "Beta", personal: false)
        await r.mock.enqueueOnce(.success(Self.response(at: 1, vaults: [upper, lower])))
        await r.store.load(Self.all)
        #expect(ids(r.store.knownVaults) == [Self.v1, Self.v2])
    }

    // MARK: iOS only

    @Test func aLoadCancelledBySwiftUIRestoresThePreviousStateOverAGraph() async {
        let r = rig()
        await r.mock.enqueueOnce(.success(Self.graph))
        await r.store.load(Self.all)
        await r.mock.enqueueOnce(.failure(CancellationError()))
        await r.store.load(Self.focused)
        #expect(stamp(r.store) == 1)
        #expect(!r.store.refreshing)
        #expect(r.store.refreshError == nil)
        #expect(!r.store.rateLimited)
        #expect(r.store.stale)
    }

    @Test func aLoadCancelledBySwiftUIRestoresAFailedState() async {
        let r = rig()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(500)))
        await r.store.load(Self.all)
        let message = failedMessage(r.store.state)
        #expect(message != nil)
        await r.mock.enqueueOnce(.failure(URLError(.cancelled)))
        await r.store.load(Self.all)
        #expect(failedMessage(r.store.state) == message)
    }

    @Test func refreshErrorClearsOnARateLimitedRequestAndOnAMissingFocus() async {
        let r = await shown()
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(500)))
        await r.store.load(BrainGraphRequest(similar: true))
        #expect(r.store.refreshError != nil)
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.rateLimited()))
        await r.store.load(Self.all)
        #expect(r.store.refreshError == nil)
        #expect(r.store.rateLimited)
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(500)))
        await r.store.load(BrainGraphRequest(similar: true))
        await r.mock.enqueueOnce(.failure(MockBrainGraphClient.httpError(404)))
        await r.store.load(Self.focused)
        #expect(r.store.refreshError == nil)
    }

    @Test func truncatedCountIsTheNoteAndMemoryNodesOfATruncatedResponse() async {
        let nodes = [
            Self.node("N1", .note), Self.node("N2", .note), Self.node("M1", .memory),
            Self.node("tag:go", .tag), Self.node("author:user:U", .author),
        ]
        let r = rig()
        #expect(r.store.truncatedCount == nil)
        await r.mock.enqueueOnce(.success(Self.response(at: 1, truncated: true, nodes: nodes)))
        await r.store.load(Self.all)
        #expect(r.store.truncatedCount == 3)
        await r.mock.enqueueOnce(.success(Self.response(at: 2, truncated: false, nodes: nodes)))
        await r.store.load(Self.all)
        #expect(r.store.truncatedCount == nil)
    }

    @Test func classifiesErrorsThroughSmallPredicates() {
        #expect(BrainGraphErrors.isRateLimited(APIError.rateLimited(retryAfter: nil)))
        #expect(BrainGraphErrors.isRateLimited(APIError.httpError(statusCode: 429, data: Data())))
        #expect(!BrainGraphErrors.isRateLimited(APIError.httpError(statusCode: 500, data: Data())))
        #expect(!BrainGraphErrors.isRateLimited(URLError(.timedOut)))
        #expect(BrainGraphErrors.isNotFound(APIError.httpError(statusCode: 404, data: Data())))
        #expect(!BrainGraphErrors.isNotFound(APIError.httpError(statusCode: 403, data: Data())))
        #expect(!BrainGraphErrors.isNotFound(APIError.unauthorized))
        #expect(BrainGraphErrors.httpStatus(APIError.httpError(statusCode: 403, data: Data())) == 403)
        #expect(BrainGraphErrors.httpStatus(APIError.rateLimited(retryAfter: nil)) == nil)
    }

    @Test func friendlyMessagesMatchTheWeb() {
        #expect(BrainGraphErrors.friendlyMessage(APIError.unauthorized) == "Session expired — sign in again.")
        #expect(BrainGraphErrors.friendlyMessage(APIError.networkFailure(URLError(.notConnectedToInternet)))
            == "Network unavailable.")
        #expect(BrainGraphErrors.friendlyMessage(APIError.rateLimited(retryAfter: nil))
            == "Too many requests. Try again in a minute.")
        #expect(BrainGraphErrors.friendlyMessage(APIError.httpError(statusCode: 429, data: Data()))
            == "Too many requests. Try again in a minute.")
        #expect(BrainGraphErrors.friendlyMessage(APIError.decodingFailed(URLError(.badServerResponse)))
            == "Unexpected server response.")
    }
}
