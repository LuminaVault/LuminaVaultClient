// LuminaVaultClient/LuminaVaultClientTests/ResurfaceNotificationsTests.swift
//
// Resurface pushes: four answers posted without opening the app, and a plain
// tap that opens the memory. Like the approval suite, the assertion that
// matters most is that none of the four answers carries `.foreground`.

import Foundation
import LuminaVaultShared
@testable import LuminaVaultClient
import Testing
import UserNotifications

@MainActor
struct ResurfaceNotificationsTests {
    private static let memoryID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    private static func category(_ id: String) throws -> UNNotificationCategory {
        try #require(HermesRunNotifications.all.first { $0.identifier == id })
    }

    // MARK: - Categories

    @Test
    func `resurface actions are the review wire values in card order`() throws {
        let category = try Self.category("resurface")
        #expect(category.actions.map(\.identifier) == ["kept", "soon", "later", "never"])
        #expect(category.actions.map(\.title) == ["Keep", "Soon", "Later", "Never"])
    }

    @Test
    func `no resurface action opens the app and only never is destructive`() throws {
        let category = try Self.category("resurface")
        for action in category.actions {
            #expect(!action.options.contains(.foreground), "\(action.identifier) must not open the app")
            #expect(action.options.contains(.destructive) == (action.identifier == "never"))
        }
    }

    @Test(arguments: [("learned", "Review"), ("brief", "Open"), ("meeting", "Open")])
    func `the plain categories carry one foreground button`(id: String, title: String) throws {
        let category = try Self.category(id)
        #expect(category.actions.count == 1)
        #expect(category.actions.first?.title == title)
        #expect(category.actions.first?.options.contains(.foreground) == true)
    }

    // MARK: - Payload

    @Test
    func `a resurface payload names its memory`() {
        let push = ResurfacePush(userInfo: [
            "category": "resurface",
            "memoryId": Self.memoryID.uuidString,
            "deepLink": "luminavault://memory/\(Self.memoryID.uuidString)",
        ])
        #expect(push?.memoryID == Self.memoryID)
    }

    @Test
    func `the category may come only from aps and the id only from the deep link`() {
        let push = ResurfacePush(userInfo: [
            "aps": ["category": "resurface"],
            "deepLink": "luminavault://memory/\(Self.memoryID.uuidString.lowercased())",
        ])
        #expect(push?.memoryID == Self.memoryID)
    }

    @Test
    func `other categories and payloads without a memory are not resurface pushes`() {
        #expect(ResurfacePush(userInfo: ["category": "chat", "memoryId": Self.memoryID.uuidString]) == nil)
        #expect(ResurfacePush(userInfo: ["category": "resurface"]) == nil)
        #expect(ResurfacePush(userInfo: ["category": "resurface", "memoryId": "nope"]) == nil)
    }

    @Test
    func `each action identifier maps to its review action`() {
        #expect(ResurfacePush.action(forActionIdentifier: "kept") == .kept)
        #expect(ResurfacePush.action(forActionIdentifier: "soon") == .soon)
        #expect(ResurfacePush.action(forActionIdentifier: "later") == .later)
        #expect(ResurfacePush.action(forActionIdentifier: "never") == .never)
        #expect(ResurfacePush.action(forActionIdentifier: UNNotificationDefaultActionIdentifier) == nil)
        #expect(ResurfacePush.action(forActionIdentifier: UNNotificationDismissActionIdentifier) == nil)
    }

    // MARK: - Routing

    @Test
    func `a tapped resurface push opens the memory`() {
        let link = NotificationRouter().deepLink(from: [
            "aps": ["category": "resurface"],
            "memoryId": Self.memoryID.uuidString,
        ])
        #expect(link == .memory(id: Self.memoryID))
    }

    @Test
    func `a category this build does not know follows its deep link`() {
        let link = NotificationRouter().deepLink(from: [
            "category": "learned",
            "deepLink": "luminavault://memory/\(Self.memoryID.uuidString)",
        ])
        #expect(link == .memory(id: Self.memoryID))
        #expect(NotificationRouter().deepLink(from: ["category": "brief"]) == .none)
    }

    @Test
    func `a resurfaced memory arriving in the foreground waits for a tap`() {
        #expect(!NotificationRouter.routesOnForegroundDelivery(.memory(id: Self.memoryID)))
    }

    // MARK: - Responder

    @Test
    func `the responder posts the action and reports the outcome`() async {
        let client = MockMemoryClient()
        client.reviewResult = .success(MemoryReviewResponse(memoryId: Self.memoryID, reviewedAt: .now, reviewCount: 2))
        let responder = ResurfaceReviewResponder(makeClient: { client })
        #expect(await responder.review(memoryID: Self.memoryID, action: .soon))
        #expect(client.reviewCalls.map(\.action) == [.soon])
        #expect(client.reviewCalls.map(\.id) == [Self.memoryID])

        client.reviewResult = .failure(APIError.unauthorized)
        #expect(await !responder.review(memoryID: Self.memoryID, action: .never))
    }
}
