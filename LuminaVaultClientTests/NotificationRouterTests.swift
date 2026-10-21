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

    // MARK: - Daily brief

    @Test
    func `the brief URL routes to the brief`() throws {
        let url = try #require(URL(string: "luminavault://brief"))
        #expect(NotificationRouter.deepLink(from: url) == .brief)
        let trailing = try #require(URL(string: "luminavault://brief/"))
        #expect(NotificationRouter.deepLink(from: trailing) == .brief)
        let shouting = try #require(URL(string: "LuminaVault://BRIEF"))
        #expect(NotificationRouter.deepLink(from: shouting) == .brief)
    }

    @Test(arguments: [
        "luminavault://brief/today",
        "https://brief",
        "luminavault://briefs",
    ])
    func `malformed brief URLs are not routed`(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(NotificationRouter.deepLink(from: url) == .none)
    }

    /// The brief's push is a `chat` push to the server (so the chat opt-out
    /// gates it) with `aps.category` `brief` and the thread its message
    /// landed in. A tap — and its "Open" action, which routes the same
    /// `userInfo` — must open the cards, not the thread.
    @Test
    func `the brief push opens the brief, not its chat thread`() {
        let router = NotificationRouter()
        #expect(router.deepLink(from: [
            "category": "chat",
            "aps": ["category": "brief"],
            "conversationID": UUID().uuidString,
            "origin": "proactive",
            "deepLink": "luminavault://brief",
        ]) == .brief)
        #expect(router.deepLink(from: [
            "aps": ["category": "brief"],
            "deepLink": "luminavault://brief",
        ]) == .brief)
    }

    @Test
    func `a chat push without the brief link still opens its thread`() {
        let id = UUID()
        let router = NotificationRouter()
        #expect(router.deepLink(from: [
            "category": "chat",
            "conversationID": id.uuidString,
            "deepLink": "luminavault://chat/\(id.uuidString)",
        ]) == .conversation(id: id))
    }

    @Test
    func `a brief push waits for a tap when the app is open`() {
        #expect(!NotificationRouter.routesOnForegroundDelivery(.brief))
    }

    /// The chat's "[Your brief is ready — 4 cards](luminavault://brief)"
    /// opens in the app; a web link still goes to the system.
    @Test
    func `app links in a chat message route in the app`() throws {
        let brief = try #require(URL(string: "luminavault://brief"))
        #expect(WikilinkMarkdownView.inAppLink(for: brief) == .brief)
        let web = try #require(URL(string: "https://luminavault.app/brief"))
        #expect(WikilinkMarkdownView.inAppLink(for: web) == nil)
        let wikilink = try #require(URL(string: "luminavault-wikilink://note?target=a&label=a"))
        #expect(WikilinkMarkdownView.inAppLink(for: wikilink) == nil)
    }

    // MARK: - Pre-meeting brief

    @Test
    func `the meeting URL routes to that meeting's brief`() throws {
        let id = UUID()
        let lower = try #require(URL(string: "luminavault://meeting/\(id.uuidString.lowercased())"))
        #expect(NotificationRouter.deepLink(from: lower) == .meeting(eventID: id))
        let shouting = try #require(URL(string: "LuminaVault://MEETING/\(id.uuidString)"))
        #expect(NotificationRouter.deepLink(from: shouting) == .meeting(eventID: id))
    }

    @Test(arguments: [
        "luminavault://meeting",
        "luminavault://meeting/not-a-uuid",
        "luminavault://meeting/0d000000-0000-4000-8000-000000000001/brief",
        "luminavault://meetings/0d000000-0000-4000-8000-000000000001",
        "https://meeting/0d000000-0000-4000-8000-000000000001",
    ])
    func `malformed meeting URLs are not routed`(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(NotificationRouter.deepLink(from: url) == .none)
    }

    /// The server's payload: `aps.category` `meeting`, `eventID` (upper-case
    /// `uuidString`) and the lower-case deep link.
    @Test
    func `the meeting push opens that meeting's brief`() {
        let id = UUID()
        let router = NotificationRouter()
        #expect(router.deepLink(from: [
            "aps": ["category": "meeting", "thread-id": "meeting"],
            "eventID": id.uuidString,
            "deepLink": "luminavault://meeting/\(id.uuidString.lowercased())",
        ]) == .meeting(eventID: id))
        #expect(router.deepLink(from: [
            "category": "meeting",
            "eventID": id.uuidString,
        ]) == .meeting(eventID: id))
        // Only the deep link: still that meeting.
        #expect(router.deepLink(from: [
            "aps": ["category": "meeting"],
            "deepLink": "luminavault://meeting/\(id.uuidString.lowercased())",
        ]) == .meeting(eventID: id))
    }

    /// Whatever else rides on it, a meeting push opens the meeting or
    /// nothing — not a chat thread, a memory, the brief or Today.
    @Test
    func `a meeting push never falls into another route`() {
        let id = UUID()
        let router = NotificationRouter()
        #expect(router.deepLink(from: [
            "category": "chat",
            "aps": ["category": "meeting"],
            "conversationID": UUID().uuidString,
            "memoryId": UUID().uuidString,
            "eventID": id.uuidString,
            "deepLink": "luminavault://brief",
        ]) == .meeting(eventID: id))
        #expect(router.deepLink(from: [
            "aps": ["category": "meeting"],
            "deepLink": "luminavault://memory/\(UUID().uuidString)",
        ]) == .none)
        #expect(router.deepLink(from: [
            "aps": ["category": "meeting"],
            "eventID": "not-a-uuid",
        ]) == .none)
    }

    @Test
    func `a meeting deep link on another category is still the meeting`() {
        let id = UUID()
        let router = NotificationRouter()
        #expect(router.deepLink(from: [
            "aps": ["category": "unknownFutureCategory"],
            "deepLink": "luminavault://meeting/\(id.uuidString.lowercased())",
        ]) == .meeting(eventID: id))
    }

    @Test
    func `a meeting push waits for a tap when the app is open`() {
        #expect(!NotificationRouter.routesOnForegroundDelivery(.meeting(eventID: UUID())))
    }

    @Test
    func `a meeting link in a chat message routes in the app`() throws {
        let id = UUID()
        let url = try #require(URL(string: "luminavault://meeting/\(id.uuidString.lowercased())"))
        #expect(WikilinkMarkdownView.inAppLink(for: url) == .meeting(eventID: id))
    }
}
