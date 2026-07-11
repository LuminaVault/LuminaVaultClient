// LuminaVaultClient/LuminaVaultClient/Features/Think/ThinkWithLuminaView.swift
// HER-107: replaces the one-shot HER-37 query surface with the multi-turn
// SSE chat from `Features/Chat/ChatView.swift`. The shell still owns:
//   - NavigationStack chrome + Lumina nav brand
//   - Toolbar link to the memo Notebook
//   - Suggestion-chip bootstrap (loaded from /v1/me/suggestions)
// Chat lifecycle, streaming, mascot states, and cancellation live in
// `ChatViewModel`.
import SwiftUI

struct ThinkWithLuminaView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.lvPalette) private var palette

    @State var chatVM: ChatViewModel
    let conversationsClient: any ConversationsClientProtocol
    let chatExperienceClient: any ChatExperienceClientProtocol
    let memoClient: MemoClientProtocol
    let suggestionsClient: SuggestionsClientProtocol
    /// HER-155 follow-up — passed to `ChatView` so finalized assistant
    /// bubbles can resolve `[[note]]` / `[[memory:uuid]]` citations
    /// inline. Optional to keep test wirings light.
    var vaultClient: (any VaultClientProtocol)?
    var memoryClient: (any MemoryClientProtocol)?
    /// Reused `/v1/vault/files` upload seam. An attached file is both
    /// extracted into the turn (immediate use) and uploaded to the vault
    /// (persisted + indexed for memory-grounding).
    var vaultUploadClient: (any VaultUploadClientProtocol)?

    @State private var suggestions: [String] = []
    @State private var showingChat = false
    @State private var activeConversationID: UUID?
    @State private var activeConversationNonce = UUID()
    /// Device-local haptics toggle (mirrors `ChatPreferencesPaneView`). Haptics
    /// are intentionally not server-synced.
    @AppStorage("lv.chat.hapticsEnabled") private var hapticsEnabled = true

    var body: some View {
        NavigationStack {
            Group {
                if showingChat {
                    activeChat
                } else {
                    ChatInboxView(
                        client: chatExperienceClient,
                        conversationsClient: conversationsClient,
                        onOpen: openConversation,
                        onNewChat: newConversation
                    )
                    .lvBackground()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await loadPreferences() }
        .onChange(of: hapticsEnabled) { _, value in chatVM.hapticsEnabled = value }
        .onChange(of: appState.pendingChatConversationID) { _, conversationID in
            openPendingConversation(conversationID)
        }
        .onAppear {
            openPendingConversation(appState.pendingChatConversationID)
        }
    }

    /// Loads the server-backed chat preferences and pushes them (plus the
    /// device-local haptics flag) onto the chat view-model so the composer +
    /// send behavior reflect the user's settings. Failures are non-fatal —
    /// the VM keeps its defaults.
    private func loadPreferences() async {
        chatVM.hapticsEnabled = hapticsEnabled
        if let response = try? await chatExperienceClient.getPreferences() {
            chatVM.autoExpandThinking = response.preferences.autoExpandThinking
            chatVM.sendOnReturn = response.preferences.sendOnReturn
        }
    }

    private var activeChat: some View {
        VStack(spacing: 0) {
            chatTopBar

            ChatView(
                viewModel: chatVM,
                emptyStateSuggestions: suggestions,
                emptyHeadline: "AI",
                emptySupporting: "Ask anything. Lumina pulls from your vault and recent learnings.",
                vaultClient: vaultClient,
                memoryClient: memoryClient,
                vaultUploadClient: vaultUploadClient,
                bottomPadding: 90
            )
        }
        .lvBackground()
        .task(id: activeConversationNonce) {
            await loadSuggestions()
            if let activeConversationID {
                await chatVM.loadConversation(id: activeConversationID)
            } else {
                chatVM.reset()
            }
        }
    }

    private var chatTopBar: some View {
        HStack(spacing: LVSpacing.sm) {
            Button {
                showingChat = false
            } label: {
                HStack(spacing: LVSpacing.xs) {
                    LVIconView(.chevronLeft, size: 13, tint: palette.textPrimary, weight: .semibold)
                    Text("Chats")
                        .font(LVTypography.callout.font.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .lvGlowPress()

            Spacer()

            Button {
                newConversation()
            } label: {
                LVIconView(.plusCircleFill, size: 22, tint: palette.glowPrimary)
            }
            .accessibilityLabel("New chat")
            .buttonStyle(.plain)
            .lvGlowPress()
        }
        .padding(.horizontal, LVSpacing.lg)
        .padding(.vertical, LVSpacing.sm)
        .background(.thinMaterial)
    }

    private func openConversation(_ id: UUID) {
        activeConversationID = id
        activeConversationNonce = UUID()
        showingChat = true
    }

    private func openPendingConversation(_ id: UUID?) {
        guard let id else { return }
        openConversation(id)
        appState.pendingChatConversationID = nil
    }

    private func newConversation() {
        activeConversationID = nil
        activeConversationNonce = UUID()
        showingChat = true
    }

    private func loadSuggestions() async {
        do {
            let response = try await suggestionsClient.list()
            suggestions = response.suggestions
        } catch {
            // Non-fatal — chips just stay hidden.
            suggestions = []
        }
    }

    private var transportIcon: String {
        switch chatVM.transport {
        case .memoryGrounded: "brain.head.profile"
        case .fresh: "cloud"
        case .hybrid: "point.3.connected.trianglepath.dotted"
        }
    }

    private var transportAccessibilityLabel: String {
        switch chatVM.transport {
        case .memoryGrounded: "Memory-grounded mode. Tap to switch to fresh Hermes."
        case .fresh: "Fresh Hermes mode. Tap to switch to hybrid execution."
        case .hybrid: "Hybrid local and cloud mode. Tap to switch to memory-grounded."
        }
    }
}
