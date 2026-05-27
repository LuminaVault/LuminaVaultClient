// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatView.swift
//
// HER-269 — multi-turn SSE chat surface. Drops into any NavigationStack
// host (Think tab, dev menu, etc.). Composer pinned via
// `.safeAreaInset(edge: .bottom)`. Auto-scrolls to the live pending
// bubble as tokens arrive.
import SwiftUI

struct ChatView: View {
    @State var viewModel: ChatViewModel
    /// HER-107 — empty-state suggestion chips (Think tab passes the
    /// server's `/v1/me/suggestions` payload). Tapping a chip seeds the
    /// composer and sends.
    var emptyStateSuggestions: [String] = []
    /// Optional empty-state copy. Defaults to a generic prompt.
    var emptyHeadline: String = "What would you like to explore today?"
    var emptySupporting: String = "Ask anything. Lumina pulls from your vault and recent learnings."
    /// HER-155 follow-up — assistant bubbles render their markdown body
    /// through `WikilinkMarkdownView` so `[[note]]` and
    /// `[[memory:<uuid>]]` citations are tappable. Both clients are
    /// optional so previews / dev menus that don't need wikilink
    /// resolution can omit them; bubbles fall back to plain text.
    var vaultClient: (any VaultClientProtocol)?
    var memoryClient: (any MemoryClientProtocol)?
    var bottomPadding: CGFloat = 0

    @FocusState private var composerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty && !viewModel.isStreaming {
                    EmptyStateHero(
                        mascotState: viewModel.mascotState,
                        headline: emptyHeadline,
                        supporting: emptySupporting,
                        suggestions: emptyStateSuggestions,
                        onSuggestion: { viewModel.sendSuggestion($0) },
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 32)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageRow(
                                message: message,
                                mascotState: .idle,
                                vaultClient: vaultClient,
                                memoryClient: memoryClient,
                            )
                                .id(message.id)
                                .contextMenu {
                                    if message.role == .assistant {
                                        Button {
                                            viewModel.saveAsMemory(message)
                                        } label: {
                                            Label("Save as memory", systemImage: "brain.head.profile")
                                        }
                                    }
                                }
                        }
                        if viewModel.isStreaming || !viewModel.pendingAssistant.isEmpty {
                            PendingAssistantRow(
                                text: viewModel.pendingAssistant,
                                sources: viewModel.pendingSources,
                                isStreaming: viewModel.isStreaming,
                                mascotState: viewModel.mascotState,
                            )
                            .id(Self.pendingAnchor)
                        }
                        if case let .failed(message) = viewModel.phase {
                            ErrorRow(message: message)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .onChange(of: viewModel.pendingAssistant) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(Self.pendingAnchor, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                guard let last = viewModel.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let toast = viewModel.savedMemoryToast {
                    SavedToast(text: toast)
                }
                if let notice = viewModel.fallbackNotice {
                    FallbackBanner(notice: notice)
                }
                Divider()
                ComposerBar(
                    text: $viewModel.composer,
                    canSend: viewModel.canSend,
                    isStreaming: viewModel.isStreaming,
                    onSend: {
                        composerFocused = false
                        viewModel.send()
                    },
                    onCancel: viewModel.cancel,
                )
                .focused($composerFocused)
            }
            .padding(.bottom, bottomPadding)
            .background(Color(.systemBackground))
        }
    }

    private static let pendingAnchor = "lv.chat.pending"
}

// MARK: - Empty state

private struct EmptyStateHero: View {
    let mascotState: HermieMascotState
    let headline: String
    let supporting: String
    let suggestions: [String]
    let onSuggestion: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            HermieMascotView(state: mascotState, size: 140, fallbackImageName: "OnboardingMascot")
            VStack(spacing: 8) {
                Text(headline)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Text(supporting)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !suggestions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(suggestions.prefix(4), id: \.self) { suggestion in
                        Button {
                            onSuggestion(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(.rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Bubbles

private struct MessageRow: View {
    let message: ChatViewModel.Message
    let mascotState: HermieMascotState
    /// HER-155 follow-up — passed through from `ChatView`. Assistant
    /// bubbles render their body via `WikilinkMarkdownView` only when
    /// both clients are present; otherwise we fall back to plain text.
    let vaultClient: (any VaultClientProtocol)?
    let memoryClient: (any MemoryClientProtocol)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 32)
                bubble
            } else {
                AssistantAvatar(state: mascotState)
                bubble
                Spacer(minLength: 32)
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            bubbleBody
            if !message.sources.isEmpty {
                SourceChipRow(sources: message.sources)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bubbleFill)
        .clipShape(.rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var bubbleBody: some View {
        // HER-155 follow-up — only assistant messages can carry
        // `[[memory:uuid]]` citations from Hermes; user messages stay
        // plain so user-entered brackets aren't rewritten.
        if message.role == .assistant,
           let vaultClient,
           let memoryClient
        {
            WikilinkMarkdownView(
                markdown: message.content,
                vaultClient: vaultClient,
                memoryClient: memoryClient,
            )
            .foregroundStyle(Color.primary)
        } else {
            Text(message.content)
                .font(.body)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .multilineTextAlignment(.leading)
        }
    }

    private var bubbleFill: Color {
        switch message.role {
        case .user: Color.accentColor
        case .assistant: Color(.secondarySystemBackground)
        case .system: Color(.tertiarySystemBackground)
        }
    }
}

private struct PendingAssistantRow: View {
    let text: String
    let sources: [QueryHitDTO]
    let isStreaming: Bool
    let mascotState: HermieMascotState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AssistantAvatar(state: mascotState)
            VStack(alignment: .leading, spacing: 4) {
                if text.isEmpty && isStreaming {
                    StreamingCaret()
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(text)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        if isStreaming { StreamingCaret() }
                    }
                }
                if !sources.isEmpty {
                    SourceChipRow(sources: sources)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
            Spacer(minLength: 32)
        }
    }
}

/// Inline assistant-turn mascot avatar. Reuses `HermieMascotView` at a
/// chat-bubble-friendly 32pt. Pending bubbles animate (`.thinking` →
/// `.happy`); finalized turns pin to `.idle` so the chat history doesn't
/// jitter as new turns arrive.
private struct AssistantAvatar: View {
    let state: HermieMascotState
    var body: some View {
        HermieMascotView(state: state, size: 32, fallbackImageName: "Mascot")
            .frame(width: 32, height: 32)
    }
}

private struct StreamingCaret: View {
    @State private var visible = true
    var body: some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: 2, height: 14)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

private struct SourceChipRow: View {
    let sources: [QueryHitDTO]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sources) { hit in
                    Text(hit.content.prefix(40))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(.capsule)
                }
            }
        }
    }
}

// MARK: - Banners + errors

private struct SavedToast: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct FallbackBanner: View {
    let notice: ProviderFallbackNoticeDTO
    var body: some View {
        Text(notice.userMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
    }
}

private struct ErrorRow: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}

// MARK: - Composer

private struct ComposerBar: View {
    @Binding var text: String
    let canSend: Bool
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask Lumina…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 16))
            if isStreaming {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Cancel reply")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
