// LuminaVaultClient/LuminaVaultClientTests/RedesignChromeSnapshotTests.swift
//
// HER-299 redesign — regression snapshots for the cinematic chrome that
// previously had no coverage. Locks in:
//   * Spaces glass cards + glow stroke (HER-307)
//   * Settings hero band mascot + glowing section rows (HER-303)
//   * Capture glass mode tabs + glowing toolbar (HER-305)
//   * Think (ChatView) empty hero — mascot + glow title + composer (HER-302)
//
// iPhone 16 Pro / .iPhone13Pro config, dark mode, animations disabled.
// To re-record: flip `isRecording = true`, run once, flip back, commit PNGs.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class RedesignChromeSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
        isRecording = false
    }
    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    private func snap(_ view: some View, _ name: String) {
        assertSnapshot(
            of: view.preferredColorScheme(.dark),
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: name
        )
    }

    // HER-307 — Spaces glass grid + glow stroke + FAB
    func testSpacesGrid() {
        let spaces: [SpaceDTO] = [
            .stub(name: "AI", category: "ai", noteCount: 4),
            .stub(name: "Health", category: "health", noteCount: 2),
            .stub(name: "Ideas", category: "ideas", noteCount: 1),
            .stub(name: "Stocks", category: "stocks", noteCount: 3),
            .stub(name: "Work", category: "work", noteCount: 5),
        ]
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let view = ZStack(alignment: .bottomTrailing) {
            Color.clear.lvBackground()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(spaces) { s in
                        SpaceCardView(space: s, onEdit: {}, onDelete: {})
                    }
                }
                .padding(20)
            }
            LVFAB {}.padding(24)
        }
        snap(view, "spaces-grid-dark")
    }

    // HER-303 — settings hero band (mascot) + glowing section rows
    func testSettingsChrome() {
        let view = ScrollView {
            VStack(spacing: LVSpacing.xl) {
                SettingsHeroBand()
                LVSectionCard("Account & Data") {
                    LVSettingsRow("Sync & Backup", icon: .arrowTriangle2Circlepath) { EmptyView() }
                    LVSettingsDivider()
                    LVSettingsRow("Privacy & Data", icon: .lockShield) { EmptyView() }
                }
                LVSectionCard("Connections") {
                    LVSettingsRow("Linked Accounts", icon: .linkCircle) { EmptyView() }
                    LVSettingsDivider()
                    LVSettingsRow("LLM Providers", icon: .brain) { EmptyView() }
                }
            }
            .padding(.horizontal, LVSpacing.lg)
            .padding(.top, LVSpacing.xl)
        }
        .background(Color.clear.lvBackground())
        snap(view, "settings-chrome-dark")
    }

    // HER-305 — capture glass mode tabs + glowing toolbar over aurora
    func testCaptureChrome() {
        snap(CaptureChromeProbe(), "capture-chrome-dark")
    }

    // HER-302 — Think empty hero (mascot + gradient title + composer)
    func testThinkEmptyHero() {
        let vm = ChatViewModel(
            conversationsClient: StubConversationsClient(),
            chatClient: StubChatClient(),
            memoryClient: StubMemoryClient(),
            historyStore: nil
        )
        let view = ChatView(
            viewModel: vm,
            emptyStateSuggestions: ["Connect \"Quantum Physics\" to \"Consciousness\"", "Draft a story idea", "Analyze recent data patterns"],
            emptyHeadline: "Think",
            emptySupporting: "Ask anything. Lumina pulls from your vault and recent learnings."
        )
        .lvBackground()
        snap(view, "think-empty-dark")
    }
}

private struct CaptureChromeProbe: View {
    @State private var mode: CaptureSheet.Mode = .photo
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AuroraBackdrop()
            CaptureMascotVignette()
            VStack {
                LVCaptureModeTabs(selected: $mode)
                    .padding(.horizontal, LVSpacing.base)
                    .padding(.top, LVSpacing.lg)
                Spacer()
                LVCaptureToolbar(canSave: true, saving: false, saveLabel: "Save (2)", onCancel: {}, onSave: {})
            }
        }
    }
}

// MARK: - Inert stub clients (Think empty-state never hits the network)

private final class StubConversationsClient: ConversationsClientProtocol, @unchecked Sendable {
    func create(_ request: ConversationCreateRequest) async throws -> ConversationDTO {
        ConversationDTO(id: UUID(), title: "", spaceId: nil, createdAt: Date(), updatedAt: Date())
    }
    func list() async throws -> ConversationListResponse { ConversationListResponse(conversations: []) }
    func get(_ id: UUID) async throws -> ConversationDetailResponse {
        ConversationDetailResponse(
            conversation: ConversationDTO(id: id, title: "", spaceId: nil, createdAt: Date(), updatedAt: Date()),
            messages: []
        )
    }
    func delete(_ id: UUID) async throws {}
    func streamReply(conversationID: UUID, request: MessageStreamRequest) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct StubChatClient: ChatClientProtocol {
    func complete(_ request: ChatRequest) async throws -> ChatResponse { throw APIError.unauthorized }
}

private struct StubMemoryClient: MemoryClientProtocol {
    func upsert(_ request: MemoryUpsertRequest) async throws -> MemoryUpsertResponse { throw APIError.unauthorized }
    func get(id: UUID) async throws -> MemoryDTO { throw APIError.unauthorized }
    func patch(id: UUID, _ request: MemoryPatchRequest) async throws -> MemoryDTO { throw APIError.unauthorized }
}
