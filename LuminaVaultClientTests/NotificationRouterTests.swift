import Foundation
@testable import LuminaVaultClient
import Testing

@MainActor
struct NotificationRouterTests {
    @Test
    func `ingestion payload routes to its batch and item`() {
        let batchID = UUID()
        let itemID = UUID()
        let router = NotificationRouter()

        let link = router.deepLink(from: [
            "category": "ingestion",
            "batchID": batchID.uuidString,
            "itemID": itemID.uuidString,
            "state": "completed",
        ])

        #expect(link == .ingestion(batchID: batchID, itemID: itemID))
    }

    @Test
    func `ingestion payload without a valid batch is ignored`() {
        let router = NotificationRouter()

        #expect(router.deepLink(from: [
            "category": "ingestion",
            "batchID": "not-a-uuid",
        ]) == .none)
    }

    @Test
    func `workflow payload routes to the Studio run monitor`() {
        let runID = UUID()
        let router = NotificationRouter()

        let link = router.deepLink(from: [
            "category": "workflow",
            "runID": runID.uuidString,
            "state": "waitingForApproval",
        ])

        #expect(link == .workflow(runID: runID))
    }

    @Test
    func `workflow payload without a valid run is ignored`() {
        let router = NotificationRouter()

        #expect(router.deepLink(from: [
            "category": "workflow",
            "runID": "not-a-uuid",
        ]) == .none)
    }

    /// `MainTabView` owns the `.workflow` link now: it consumes on arrival and
    /// hands the run id to `WorkflowListView` as `initialRunID`. This pins the
    /// half the router is responsible for — a consume hands the link over once
    /// and leaves nothing behind for a second host to re-present.
    @Test
    func `consuming a workflow link yields its run once and clears it`() {
        let runID = UUID()
        let router = NotificationRouter()
        router.pendingDeepLink = router.deepLink(from: [
            "category": "workflow",
            "runID": runID.uuidString,
        ])

        #expect(router.consume() == .workflow(runID: runID))
        #expect(router.pendingDeepLink == .none)
        #expect(router.consume() == .none)
    }

    // MARK: - Hermes runs (Phase 1)

    @Test
    func `an approval push opens the run it is blocked on`() {
        let runID = UUID()
        let router = NotificationRouter()

        let link = router.deepLink(from: [
            "category": "approval",
            "runID": runID.uuidString,
            "hermesRunID": "run_ab12",
            "status": "waiting_for_approval",
            "choices": "once,session,deny",
        ])

        #expect(link == .hermesRun(runID: runID))
    }

    @Test
    func `a run completed push opens the same run`() {
        let runID = UUID()
        let router = NotificationRouter()

        let link = router.deepLink(from: [
            "category": "runCompleted",
            "runID": runID.uuidString,
            "status": "completed",
        ])

        #expect(link == .hermesRun(runID: runID))
    }

    @Test
    func `a hermes run push without a run id is ignored`() {
        let router = NotificationRouter()

        #expect(router.deepLink(from: [
            "category": "approval",
            "hermesRunID": "run_ab12",
        ]) == .none)
    }
}
