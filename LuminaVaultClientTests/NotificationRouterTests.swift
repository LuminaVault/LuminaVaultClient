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
}
