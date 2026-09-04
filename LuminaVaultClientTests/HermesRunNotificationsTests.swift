// LuminaVaultClient/LuminaVaultClientTests/HermesRunNotificationsTests.swift
//
// Hermes Companion Phase 1 — answering an approval from the lock screen.
//
// The load-bearing assertion in this file is that no approval action carries
// `.foreground`. The entire pitch is "answer without opening the app"; a
// single stray option would turn every answer into an app launch and nobody
// would notice from a screenshot.

import Foundation
import LuminaVaultShared
@testable import LuminaVaultClient
import Testing
import UserNotifications

@MainActor
struct HermesRunNotificationsTests {
    private static let runID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    private static func approvalCategory() throws -> UNNotificationCategory {
        try #require(
            HermesRunNotifications.all.first { $0.identifier == HermesRunNotifications.approvalCategoryID }
        )
    }

    // MARK: - Categories

    @Test
    func `both hermes run categories are registered`() {
        let identifiers = Set(HermesRunNotifications.all.map(\.identifier))
        #expect(identifiers == ["approval", "runCompleted"])
    }

    @Test
    func `approval actions are the wire choice values`() throws {
        let category = try Self.approvalCategory()
        // The identifiers are posted verbatim to
        // POST /v1/hermes/runs/:id/approval, so they must be the enum's raw
        // values and nothing prettier.
        #expect(Set(category.actions.map(\.identifier)) == ["once", "session", "always", "deny"])
    }

    @Test
    func `no approval action opens the app`() throws {
        let category = try Self.approvalCategory()
        for action in category.actions {
            #expect(!action.options.contains(.foreground), "\(action.identifier) would launch the app")
        }
    }

    @Test
    func `allowing a tool call requires an unlocked phone but denying does not`() throws {
        let category = try Self.approvalCategory()
        for action in category.actions {
            if action.identifier == HermesApprovalChoice.deny.rawValue {
                #expect(action.options.contains(.destructive))
                #expect(!action.options.contains(.authenticationRequired))
            } else {
                #expect(action.options.contains(.authenticationRequired))
            }
        }
    }

    @Test
    func `action titles match the in-app approval card`() throws {
        let category = try Self.approvalCategory()
        for action in category.actions {
            let choice = try #require(HermesApprovalChoice(rawValue: action.identifier))
            #expect(action.title == HermesRunApprovalCard.label(for: choice))
        }
    }

    @Test
    func `run completed is a plain category with nothing to answer`() throws {
        let category = try #require(
            HermesRunNotifications.all.first { $0.identifier == HermesRunNotifications.runCompletedCategoryID }
        )
        #expect(category.actions.isEmpty)
    }

    // MARK: - Payload

    @Test
    func `approval payload parses the comma separated choices`() throws {
        let push = try #require(HermesApprovalPush(userInfo: [
            "category": "approval",
            "runID": Self.runID.uuidString,
            "hermesRunID": "run_ab12",
            "status": "waiting_for_approval",
            "choices": "once,session,deny",
        ]))

        #expect(push.runID == Self.runID)
        #expect(push.hermesRunID == "run_ab12")
        #expect(push.choices == [.once, .session, .deny])
    }

    @Test
    func `unknown choices in the payload are dropped rather than failing the parse`() throws {
        let push = try #require(HermesApprovalPush(userInfo: [
            "category": "approval",
            "runID": Self.runID.uuidString,
            "choices": "once, maybe ,deny",
        ]))

        #expect(push.choices == [.once, .deny])
    }

    @Test
    func `a payload from another category is not an approval`() {
        #expect(HermesApprovalPush(userInfo: [
            "category": "runCompleted",
            "runID": Self.runID.uuidString,
        ]) == nil)
    }

    @Test
    func `an approval without a run id is not actionable`() {
        #expect(HermesApprovalPush(userInfo: [
            "category": "approval",
            "choices": "once,deny",
        ]) == nil)
    }

    // MARK: - Choosing

    @Test
    func `only choices the run offered are answerable`() throws {
        let push = try #require(HermesApprovalPush(userInfo: [
            "category": "approval",
            "runID": Self.runID.uuidString,
            "choices": "once,deny",
        ]))

        #expect(push.choice(forActionIdentifier: "once") == .once)
        #expect(push.choice(forActionIdentifier: "deny") == .deny)
        // The category renders every answer Hermes can ever ask for, but this
        // run withheld `always` — sending it would be rejected upstream.
        #expect(push.choice(forActionIdentifier: "always") == nil)
    }

    @Test
    func `the default tap is not an answer`() throws {
        let push = try #require(HermesApprovalPush(userInfo: [
            "category": "approval",
            "runID": Self.runID.uuidString,
            "choices": "once,deny",
        ]))

        #expect(push.choice(forActionIdentifier: UNNotificationDefaultActionIdentifier) == nil)
        #expect(push.choice(forActionIdentifier: UNNotificationDismissActionIdentifier) == nil)
    }

    // MARK: - Responder

    @Test
    func `answering posts the tapped choice for the run in the payload`() async {
        let client = StubHermesRunsClient()
        let responder = HermesApprovalResponder(makeClient: { client })

        let accepted = await responder.answer(runID: Self.runID, choice: .session)

        #expect(accepted)
        #expect(client.approvedChoices == [.session])
    }

    /// A notification action has nowhere to show an error, so the responder
    /// reports failure instead of throwing; the app delegate turns that into
    /// a deep link so the prompt is not silently lost.
    @Test
    func `a rejected answer reports failure instead of throwing`() async {
        let client = StubHermesRunsClient()
        client.approveResult = .failure(
            APIError.httpError(
                statusCode: 409,
                data: Data(#"{"error":{"message":"hermes_approval_not_pending"}}"#.utf8)
            )
        )
        let responder = HermesApprovalResponder(makeClient: { client })

        let accepted = await responder.answer(runID: Self.runID, choice: .once)

        #expect(!accepted)
    }
}
