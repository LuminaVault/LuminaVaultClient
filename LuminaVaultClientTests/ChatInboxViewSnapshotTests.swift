// LuminaVaultClient/LuminaVaultClientTests/ChatInboxViewSnapshotTests.swift
//
// The AI tab's root: one navigation title, one "New chat" action, and rows
// that say what the thread is about. The populated case deliberately carries
// a row the server still calls "New conversation" and a row with a single
// message — the two things the old list got visibly wrong.
//
// Recording is ON in this suite. Baselines cannot be recorded on an Xcode
// 26.2 machine against CI's iOS 26.4 renderer, so CI writes them on the first
// run and Task 7 turns recording back off with the PNGs committed.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class ChatInboxViewSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
        isRecording = true
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        isRecording = false
        super.tearDown()
    }

    // MARK: - Fixtures

    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: "0000000\(n)-1111-4222-8333-444444444444")!
    }

    /// Offsets from *now*, not fixed instants: the row formats
    /// `.relative(presentation: .named)`, so a pinned epoch renders "last
    /// year" and drifts to "2 years ago" the moment the calendar turns over.
    /// The offsets are small — well under three hours — because that
    /// presentation says "yesterday" for anything on the previous calendar
    /// day, so a longer reach back changes the render with the time of day
    /// the suite happens to run.
    private static func ago(_ seconds: TimeInterval) -> Date {
        Date().addingTimeInterval(-seconds)
    }

    private static let items: [ChatInboxItemDTO] = [
        ChatInboxItemDTO(
            id: id(1),
            title: "Sealed secrets for horus",
            preview: "A blob is bound to both the namespace and the secret name, so resealing is the fix.",
            messageCount: 12,
            lastMessageAt: ago(9 * 60),
            sourceLabel: "Lumina"
        ),
        // The server never renamed this one; the row has to derive a title.
        ChatInboxItemDTO(
            id: id(2),
            title: "New conversation",
            preview: "How long does the whisper service take on a two-minute voice note?",
            messageCount: 4,
            lastMessageAt: ago(47 * 60),
            sourceLabel: "Lumina"
        ),
        // One message, which used to read "1 messages".
        ChatInboxItemDTO(
            id: id(3),
            title: "New conversation",
            preview: "Draft the demand-hour note",
            messageCount: 1,
            lastMessageAt: ago(2 * 60 * 60),
            sourceLabel: "Lumina"
        ),
    ]

    private func makeViewModel(
        outcome: StubChatInboxClient.Outcome,
        items: [ChatInboxItemDTO] = [],
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) -> ChatInboxViewModel {
        let vm = ChatInboxViewModel(
            client: StubChatInboxClient(outcome: outcome),
            conversationsClient: InertConversationsClient()
        )
        // Seeded *and* reproducible from the stub, so the render is the same
        // whether or not the view's `.task` has landed yet.
        vm.items = items
        vm.isLoading = isLoading
        vm.errorMessage = errorMessage
        return vm
    }

    private func makeView(_ viewModel: ChatInboxViewModel) -> some View {
        NavigationStack {
            ChatInboxView(viewModel: viewModel, onOpen: { _ in }, onNewChat: {})
                .navigationTitle("AI")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New chat", systemImage: "square.and.pencil") {}
                    }
                }
        }
    }

    private func snap(_ view: some View, _ name: String, dark: Bool) {
        assertSnapshot(
            of: view
                .environment(\.lvAmbientMotionEnabled, false)
                .environment(AppState())
                .environment(\.locale, Locale(identifier: "en_US"))
                // The app resolves the palette per colour scheme through
                // `LVThemeManager`; without one the environment default is the
                // dark palette, which renders light-mode text nearly white.
                .environment(\.lvPalette, LVTheme.cyanGold.palette(for: dark ? .dark : .light))
                // `MainTabView` tints the whole tab set, so bar buttons here
                // render in the accent rather than the default blue.
                .tint(LVTheme.cyanGold.palette(for: dark ? .dark : .light).accent)
                .preferredColorScheme(dark ? .dark : .light),
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: dark ? .dark : .light)
            ),
            // `testName` rather than `named`, so the baseline is called what
            // the case is called instead of carrying this helper's signature
            // and a misleading "dark" into every file name.
            testName: name
        )
    }

    // MARK: - Cases

    func testPopulated() {
        let vm = makeViewModel(outcome: .items(Self.items), items: Self.items)
        snap(makeView(vm), "inbox-populated-light", dark: false)
        snap(makeView(vm), "inbox-populated-dark", dark: true)
    }

    func testLoading() {
        let vm = makeViewModel(outcome: .hang, isLoading: true)
        snap(makeView(vm), "inbox-loading-light", dark: false)
        snap(makeView(vm), "inbox-loading-dark", dark: true)
    }

    func testFailure() {
        let vm = makeViewModel(
            outcome: .failure,
            errorMessage: InboxUnavailable().localizedDescription
        )
        snap(makeView(vm), "inbox-failure-light", dark: false)
        snap(makeView(vm), "inbox-failure-dark", dark: true)
    }
}

private struct InboxUnavailable: LocalizedError {
    var errorDescription: String? { "The network connection was lost." }
}

/// The inbox reads one endpoint; preferences belong to the AI tab's shell and
/// are never asked for here.
private struct StubChatInboxClient: ChatExperienceClientProtocol {
    enum Outcome: Sendable {
        case items([ChatInboxItemDTO])
        case failure
        /// Never returns, so the view stays in its loading state.
        case hang
    }

    let outcome: Outcome

    func inbox(limit _: Int) async throws -> ChatInboxResponse {
        switch outcome {
        case let .items(items):
            return ChatInboxResponse(items: items)
        case .failure:
            throw InboxUnavailable()
        case .hang:
            try await Task.sleep(for: .seconds(600))
            throw CancellationError()
        }
    }

    func getPreferences() async throws -> ChatPreferencesGetResponse {
        throw InboxUnavailable()
    }

    func putPreferences(_: ChatPreferencesDTO) async throws -> ChatPreferencesGetResponse {
        throw InboxUnavailable()
    }
}

/// Swiping a row to delete is not snapshotted, so nothing here needs to work.
private struct InertConversationsClient: ConversationsClientProtocol {
    func create(_: ConversationCreateRequest) async throws -> ConversationDTO {
        throw InboxUnavailable()
    }

    func list() async throws -> ConversationListResponse {
        throw InboxUnavailable()
    }

    func get(_: UUID) async throws -> ConversationDetailResponse {
        throw InboxUnavailable()
    }

    func delete(_: UUID) async throws {
        throw InboxUnavailable()
    }

    func streamReply(
        conversationID _: UUID,
        request _: MessageStreamRequest
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: InboxUnavailable()) }
    }
}
