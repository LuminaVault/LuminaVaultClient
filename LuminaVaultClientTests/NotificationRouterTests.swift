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

    @Test
    func `a memory URL opens that memory`() throws {
        let memoryID = UUID()
        let url = try #require(URL(string: "luminavault://memory/\(memoryID.uuidString)"))

        #expect(NotificationRouter.deepLink(from: url) == .memory(id: memoryID))
    }

    @Test
    func `a memory URL is matched case-insensitively and takes a lowercased id`() throws {
        let memoryID = UUID()
        let url = try #require(URL(string: "LuminaVault://Memory/\(memoryID.uuidString.lowercased())"))

        #expect(NotificationRouter.deepLink(from: url) == .memory(id: memoryID))
    }

    @Test(arguments: [
        "luminavault://memory/not-a-uuid",
        "luminavault://memory",
        "luminavault://memory/7C0E0B53-9A51-4F43-9B0C-2C1E6B0E0001/extra",
        "https://memory/7C0E0B53-9A51-4F43-9B0C-2C1E6B0E0001",
        "luminavault://memories/7C0E0B53-9A51-4F43-9B0C-2C1E6B0E0001",
    ])
    func `malformed memory URLs are not routed`(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(NotificationRouter.deepLink(from: url) == .none)
    }

    /// A memory push is a resurfaced memory coming due; like a chat push,
    /// its banner is the news, and only a tap opens it. (A memory *URL* —
    /// a widget tap, a link — goes through `onOpenURL`, not this check.)
    @Test
    func `a memory push waits for a tap when the app is open`() {
        #expect(!NotificationRouter.routesOnForegroundDelivery(.memory(id: UUID())))
    }

    // MARK: - What I learned this week

    @Test
    func `the learned URL routes to the weekly sheet`() throws {
        let url = try #require(URL(string: "luminavault://learned"))
        #expect(NotificationRouter.deepLink(from: url) == .learned)
        let trailing = try #require(URL(string: "luminavault://learned/"))
        #expect(NotificationRouter.deepLink(from: trailing) == .learned)
    }

    @Test(arguments: [
        "luminavault://learned/7C0E0B53-9A51-4F43-9B0C-2C1E6B0E0001",
        "https://learned",
        "luminavault://learnt",
    ])
    func `malformed learned URLs are not routed`(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(NotificationRouter.deepLink(from: url) == .none)
    }

    /// The `learned` push is not an `APNSCategory`; its tap and its "Review"
    /// action both route through the payload's `deepLink`.
    @Test
    func `a learned push opens wherever its deep link points`() {
        let router = NotificationRouter()
        #expect(router.deepLink(from: [
            "category": "learned",
            "deepLink": "luminavault://learned",
        ]) == .learned)
        #expect(router.deepLink(from: [
            "aps": ["category": "learned"],
            "deepLink": "luminavault://learned",
        ]) == .learned)
        #expect(router.deepLink(from: ["category": "learned"]) == .none)
    }

    @Test
    func `a learned push waits for a tap when the app is open`() {
        #expect(!NotificationRouter.routesOnForegroundDelivery(.learned))
    }
}
