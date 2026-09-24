// LuminaVaultClient/LuminaVaultClient/Features/Think/ThinkWithLuminaView.swift
// HER-107: replaces the one-shot HER-37 query surface with the multi-turn
// SSE chat from `Features/Chat/ChatView.swift`. The shell still owns:
//   - the AI tab's NavigationStack and its navigation title
//   - the single "New chat" action
//   - Suggestion-chip bootstrap (loaded from /v1/me/suggestions)
// Chat lifecycle, streaming, mascot states, and cancellation live in
// `ChatViewModel`.
import SwiftUI

/// Where the AI tab can navigate. A `nil` id is a thread that does not exist
/// yet — the first send creates it.
enum ChatRoute: Hashable {
    case conversation(UUID?)
}

struct ThinkWithLuminaView: View {
    @Environment(AppState.self) private var appState

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
    /// A chat is pushed, so it gets the system back button instead of a
    /// hand-rolled "Chats" chevron.
    @State private var path: [ChatRoute] = []
    /// Device-local haptics toggle (mirrors `ChatPreferencesPaneView`). Haptics
    /// are intentionally not server-synced.
    @AppStorage("lv.chat.hapticsEnabled") private var hapticsEnabled = true
    /// "Get started with Hermie". Optional so the AI tab still stands up in
    /// previews and tests with no shell around it.
    @Environment(GuidedStartCoordinator.self) private var guided: GuidedStartCoordinator?

    var body: some View {
        NavigationStack(path: $path) {
            ChatInboxView(
                client: chatExperienceClient,
                conversationsClient: conversationsClient,
                onOpen: openConversation,
                onNewChat: newConversation
            )
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New chat", systemImage: "square.and.pencil") {
                        newConversation()
                    }
                }
            }
            .navigationDestination(for: ChatRoute.self) { route in
                chatDetail(route)
            }
        }
        .task { await loadPreferences() }
        .onChange(of: hapticsEnabled) { _, value in chatVM.hapticsEnabled = value }
        .onChange(of: appState.pendingChatConversationID) { _, conversationID in
            openPendingConversation(conversationID)
        }
        .onChange(of: appState.pendingChatPrefill) { _, prefill in
            applyPendingPrefill(prefill)
        }
        .onAppear {
            openPendingConversation(appState.pendingChatConversationID)
            applyPendingPrefill(appState.pendingChatPrefill)
            // The tab may have been unvisited when the step opened, in which
            // case this is the first chance to act on it.
            showRootChatForGuidedStep()
        }
        // Step 3 spotlights the chat composer, and the composer only exists
        // on the chat screen — the inbox at the root of this stack has none.
        // So when the wizard asks for this tab, reset the stack to the root
        // chat, which is what publishes the `.chat` anchor.
        .onChange(of: guided?.activeStep) { _, _ in
            showRootChatForGuidedStep()
        }
    }

    private func showRootChatForGuidedStep() {
        guard guided?.activeStep == .ask else { return }
        showRootChat()
    }

    /// Puts the chat composer on screen. An already-open thread is left
    /// alone — it has a composer of its own, and yanking the user out of a
    /// conversation to teach them how to have one would be absurd.
    private func showRootChat() {
        guard path.isEmpty else { return }
        newConversation()
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

    private func chatDetail(_ route: ChatRoute) -> some View {
        ChatView(
            viewModel: chatVM,
            emptyStateSuggestions: suggestions,
            emptyHeadline: "AI",
            emptySupporting: "Ask anything. Lumina pulls from your vault and recent learnings.",
            vaultClient: vaultClient,
            memoryClient: memoryClient,
            vaultUploadClient: vaultUploadClient
        )
        .task {
            await loadSuggestions()
            guard case let .conversation(id) = route else { return }
            if let id {
                await chatVM.loadConversation(id: id)
            } else {
                chatVM.reset()
            }
        }
    }

    /// One chat at a time on the stack: opening another thread replaces the
    /// one that was open, so Back always lands on the inbox.
    private func openConversation(_ id: UUID) {
        path = [.conversation(id)]
    }

    private func openPendingConversation(_ id: UUID?) {
        guard let id else { return }
        if path == [.conversation(id)] {
            // Already on screen — a proactive push for the open thread. The
            // route's `.task` will not re-run, so pull the new message in
            // here. `loadConversation` declines while a turn is in flight.
            Task { await chatVM.loadConversation(id: id) }
        } else {
            openConversation(id)
        }
        appState.pendingChatConversationID = nil
    }

    private func applyPendingPrefill(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        newConversation()
        chatVM.composer = text
        appState.pendingChatPrefill = nil
    }

    private func newConversation() {
        path = [.conversation(nil)]
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
}
