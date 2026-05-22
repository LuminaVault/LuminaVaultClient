// LuminaVaultClient/LuminaVaultClientTests/SessionsListViewSnapshotTests.swift
//
// HER-263 — image snapshots for the OS Shell Sessions list. Populated
// dark + light + empty dark variants.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class SessionsListViewSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
        isRecording = false
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    private final class StubSessionsClient: SessionsClientProtocol, @unchecked Sendable {
        let result: Result<SessionListResponse, Error>
        init(result: Result<SessionListResponse, Error>) { self.result = result }
        func list(limit: Int?, workspaceID: UUID?) async throws -> SessionListResponse {
            try result.get()
        }
    }

    private static func stubSession(title: String, preview: String, messages: Int, daysAgo: Int) -> SessionDTO {
        SessionDTO(
            id: UUID(),
            title: title,
            preview: preview,
            messageCount: messages,
            lastMessageAt: Date(timeIntervalSinceNow: TimeInterval(-daysAgo * 86_400)),
            workspaceID: nil,
            pinned: false,
            archived: false
        )
    }

    private func makeView(populated: Bool) -> some View {
        let canned: [SessionDTO] = populated ? [
            Self.stubSession(title: "Trip to Lisbon", preview: "We landed late but the place is great…", messages: 12, daysAgo: 0),
            Self.stubSession(title: "Memo on linear algebra", preview: "Vector spaces and linear transformations…", messages: 4, daysAgo: 1),
            Self.stubSession(title: "Pattern across kb-compile errors", preview: "Three timeouts at 7am, all on Wednesdays…", messages: 8, daysAgo: 3),
        ] : []
        let client = StubSessionsClient(result: .success(SessionListResponse(sessions: canned)))
        let vm = SessionsListViewModel(client: client)
        vm.sessions = canned
        vm.state = .loaded
        return NavigationStack {
            SessionsListView(vm: vm)
        }
        .environment(WorkspaceSelection())
        .transaction { $0.disablesAnimations = true }
    }

    func testSessionsPopulatedDarkMode() {
        let view = makeView(populated: true).preferredColorScheme(.dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: "iPhone16Pro-populated-dark"
        )
    }

    func testSessionsPopulatedLightMode() {
        let view = makeView(populated: true).preferredColorScheme(.light)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .light)
            ),
            named: "iPhone16Pro-populated-light"
        )
    }

    func testSessionsEmptyDarkMode() {
        let view = makeView(populated: false).preferredColorScheme(.dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: "iPhone16Pro-empty-dark"
        )
    }
}
