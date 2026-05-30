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

    @Environment(\.lvPalette) private var palette

    @State var chatVM: ChatViewModel
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

    var body: some View {
        NavigationStack {
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
            .lvBackground()
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await chatVM.restore()
                await loadSuggestions()
            }
        }
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
        }
    }

    private var transportAccessibilityLabel: String {
        switch chatVM.transport {
        case .memoryGrounded: "Memory-grounded mode. Tap to switch to fresh Hermes."
        case .fresh: "Fresh Hermes mode. Tap to switch to memory-grounded."
        }
    }
}
