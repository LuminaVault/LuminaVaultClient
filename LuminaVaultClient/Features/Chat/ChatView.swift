// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatView.swift
//
// HER-269 — multi-turn SSE chat surface. Drops into any NavigationStack
// host (AI tab, dev menu, etc.). Composer pinned via
// `.safeAreaInset(edge: .bottom)`. Auto-scrolls to the live pending
// bubble as tokens arrive.
//
// The empty state is an "Input Hub": a shared cosmic background, a
// Hermie status badge, and a horizontal carousel of quick-action cards
// above the composer. Both empty and active states share the same
// background + composer so switching between them is seamless, and the
// quick actions sit well above the composer so they can never overlap
// or intercept its taps (the cause of the old "typed send does nothing"
// bug — full-width suggestion buttons stole the send tap).
import SwiftUI

struct ChatView: View {
    @Environment(\.lvPalette) private var palette
    @State var viewModel: ChatViewModel
    /// HER-107 — empty-state quick actions (the AI tab passes the
    /// server's `/v1/me/suggestions` payload). Tapping a card seeds the
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
    /// Reused `/v1/vault/files` upload seam. An attached file is both
    /// extracted into the turn and uploaded to the vault (persisted +
    /// indexed for grounding). Optional so previews / dev menus can omit.
    var vaultUploadClient: (any VaultUploadClientProtocol)?
    var bottomPadding: CGFloat = 0

    @FocusState private var composerFocused: Bool
    /// Transient banner for a failed file extraction (unsupported type,
    /// unreadable, empty). Auto-clears after a few seconds.
    @State private var attachmentError: String?

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ChatCosmicBackground()

                ScrollView {
                    VStack(spacing: LVSpacing.lg) {
                        if viewModel.messages.isEmpty && !viewModel.isStreaming {
                            emptyState
                        } else {
                            conversation
                        }
                    }
                    .padding(.top, LVSpacing.base)
                    // Clearance so content never hides under the composer.
                    .padding(.bottom, LVSpacing.hero)
                }
                .onChange(of: viewModel.displayedAssistant) { _, _ in
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
            // HER-255 — header hoisted to MainTabView (app-wide base header).
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
    }

    // MARK: - Empty state ("Input Hub")

    private var emptyState: some View {
        VStack(spacing: LVSpacing.xl) {
            HermieStatusBadge(mascotState: viewModel.mascotState, label: statusLabel)
                .padding(.top, LVSpacing.lg)

            if !emptyStateSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: LVSpacing.sm) {
                    Text("Quick actions")
                        .lvFont(.microTag)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, LVSpacing.lg)

                    QuickActionsCarousel(
                        suggestions: emptyStateSuggestions,
                        onTap: { viewModel.sendSuggestion($0) }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !emptySupporting.isEmpty {
                Text(emptySupporting)
                    .lvFont(.callout)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LVSpacing.lg)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Short label under the mascot badge, derived from voice + phase.
    private var statusLabel: String {
        if viewModel.voice.isRecording { return "Listening…" }
        switch viewModel.phase {
        case .starting, .streaming: return "Thinking…"
        case .failed: return "Let's try that again"
        case .idle: return "Ready when you are"
        }
    }

    // MARK: - Active conversation

    private var conversation: some View {
        LazyVStack(alignment: .leading, spacing: LVSpacing.base) {
            HStack {
                Spacer()
                Button {
                    viewModel.reset()
                } label: {
                    LVIconView(.trash, size: 14, tint: palette.textSecondary)
                }
                .lvGlowPress()
            }
            .padding(.bottom, LVSpacing.sm)

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
                    text: viewModel.displayedAssistant,
                    sources: viewModel.pendingSources,
                    isStreaming: viewModel.isStreaming,
                    mascotState: viewModel.mascotState,
                )
                .id(Self.pendingAnchor)
            }

            if case let .failed(message) = viewModel.phase {
                ErrorRow(message: message, onRetry: { viewModel.retryLast() })
            }
        }
        .padding(.horizontal, LVSpacing.lg)
    }

    // MARK: - Bottom bar (toasts + composer)

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if let toast = viewModel.savedMemoryToast {
                SavedToast(text: toast)
            }
            if let notice = viewModel.fallbackNotice {
                FallbackBanner(notice: notice)
            }
            if let voiceError = viewModel.voice.errorMessage {
                VoiceErrorToast(text: voiceError)
            }
            if let attachmentError {
                VoiceErrorToast(text: attachmentError)
            }

            ComposerBar(
                text: $viewModel.composer,
                canSend: viewModel.canSend,
                isStreaming: viewModel.isStreaming,
                stagedAttachmentName: viewModel.stagedAttachment?.name,
                voice: viewModel.voice,
                onSend: {
                    composerFocused = false
                    viewModel.send()
                },
                onCancel: viewModel.cancel,
                onAttach: handleAttach,
                onClearAttachment: viewModel.clearAttachment,
            )
            .focused($composerFocused)
        }
        .padding(.bottom, bottomPadding)
        .background(.clear)
    }

    /// "Do both": extract the file's text into the turn (immediate use)
    /// AND upload the raw bytes to the vault (persisted + indexed for
    /// grounding). The upload is best-effort — the staged text works even
    /// if the vault rejects the type.
    private func handleAttach(_ url: URL) {
        do {
            let extracted = try AttachmentTextExtractor.extract(from: url)
            viewModel.attach(name: extracted.name, text: extracted.text)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            showAttachmentError(message)
            return
        }
        uploadToVault(url)
    }

    private func uploadToVault(_ url: URL) {
        guard let vaultUploadClient else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if scoped { url.stopAccessingSecurityScopedResource() }
        guard let data else { return }

        let name = url.lastPathComponent
        let contentType = Self.uploadContentType(for: url.pathExtension.lowercased())
        Task {
            // Best-effort: a vault allowlist rejection (e.g. .txt) leaves
            // the staged text intact, so the turn still carries the file.
            _ = try? await vaultUploadClient.uploadAsset(
                data: data,
                contentType: contentType,
                relativePath: "uploads/\(name)",
                spaceID: nil,
            )
        }
    }

    private static func uploadContentType(for ext: String) -> String {
        switch ext {
        case "pdf": return "application/pdf"
        case "md", "markdown": return "text/markdown"
        default: return "text/plain"
        }
    }

    private func showAttachmentError(_ message: String) {
        attachmentError = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            attachmentError = nil
        }
    }

    private static let pendingAnchor = "lv.chat.pending"
}

// MARK: - Bubbles

private struct MessageRow: View {
    @Environment(\.lvPalette) private var palette
    let message: ChatViewModel.Message
    let mascotState: HermieMascotState
    /// HER-155 follow-up — passed through from `ChatView`. Assistant
    /// bubbles render their body via `WikilinkMarkdownView` only when
    /// both clients are present; otherwise we fall back to plain text.
    let vaultClient: (any VaultClientProtocol)?
    let memoryClient: (any MemoryClientProtocol)?

    var body: some View {
        HStack(alignment: .top, spacing: LVSpacing.sm) {
            if message.role == .user {
                Spacer(minLength: LVSpacing.hero)
                bubble
            } else {
                AssistantAvatar(state: mascotState)
                    .padding(.top, LVSpacing.xs)
                bubble
                Spacer(minLength: LVSpacing.hero)
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        let content = VStack(alignment: .leading, spacing: LVSpacing.xs) {
            bubbleBody
            if !message.sources.isEmpty {
                SourceChipRow(sources: message.sources)
            }
        }
        .padding(.horizontal, LVSpacing.base)
        .padding(.vertical, LVSpacing.md)

        if message.role == .user {
            content
                .background {
                    RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
                        .fill(palette.glowPrimary.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
                                .stroke(palette.glowPrimary.opacity(0.5), lineWidth: 1)
                        }
                }
                .shadow(color: palette.glowPrimary.opacity(0.25), radius: 10)
        } else {
            content
                .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.card)
                .lvInnerGlow(cornerRadius: LVRadius.card, intensity: LVGlow.subtle)
        }
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
            .foregroundStyle(palette.textPrimary)
        } else {
            Text(message.content)
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.leading)
        }
    }
}

private struct PendingAssistantRow: View {
    @Environment(\.lvPalette) private var palette
    let text: String
    let sources: [QueryHitDTO]
    let isStreaming: Bool
    let mascotState: HermieMascotState

    var body: some View {
        HStack(alignment: .top, spacing: LVSpacing.sm) {
            AssistantAvatar(state: mascotState)
                .padding(.top, LVSpacing.xs)
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                if text.isEmpty && isStreaming {
                    StreamingCaret()
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: LVSpacing.xs) {
                        Text(text)
                            .lvFont(.body)
                            .foregroundStyle(palette.textPrimary)
                            .multilineTextAlignment(.leading)
                        if isStreaming { StreamingCaret() }
                    }
                }
                if !sources.isEmpty {
                    SourceChipRow(sources: sources)
                }
            }
            .padding(.horizontal, LVSpacing.base)
            .padding(.vertical, LVSpacing.md)
            .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.card)
            .lvInnerGlow(cornerRadius: LVRadius.card,
                         intensity: isStreaming ? LVGlow.focused : LVGlow.subtle)
            .lvPulse(active: isStreaming)
            Spacer(minLength: LVSpacing.hero)
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
    @Environment(\.lvPalette) private var palette
    @State private var visible = true
    var body: some View {
        Rectangle()
            .fill(palette.glowPrimary)
            .frame(width: 2, height: 14)
            .shadow(color: palette.glowPrimary.opacity(0.8), radius: 4)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

private struct SourceChipRow: View {
    @Environment(\.lvPalette) private var palette
    let sources: [QueryHitDTO]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LVSpacing.sm) {
                ForEach(sources) { hit in
                    Text(hit.content.prefix(40))
                        .lvFont(.microTag)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, LVSpacing.sm)
                        .padding(.vertical, LVSpacing.xs)
                        .background(
                            Capsule().fill(palette.surface)
                        )
                        .overlay {
                            Capsule()
                                .stroke(palette.glowPrimary.opacity(0.25), lineWidth: 1)
                        }
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
            LVIconView(.checkmarkCircleFill, size: 17, tint: .green)
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

/// HER-153 — transient banner above the composer surfacing voice mode
/// failures (mic denied, no speech detected, recognizer unavailable) and
/// file-attachment failures. Auto-decays via its source state.
private struct VoiceErrorToast: View {
    @Environment(\.lvPalette) private var palette
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            LVIconView(.exclamationmarkTriangleFill, size: 14, tint: .orange)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct ErrorRow: View {
    @Environment(\.lvPalette) private var palette
    let message: String
    /// Re-sends the last user turn. Surfaced as a tappable "Retry" pill so
    /// a timed-out / failed reply is recoverable without retyping.
    var onRetry: (() -> Void)?
    var body: some View {
        HStack(spacing: 8) {
            LVIconView(.exclamationmarkTriangleFill, size: 14, tint: .orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        LVIconView(.arrowUpCircleFill, size: 13, tint: palette.glowPrimary)
                        Text("Retry")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.glowPrimary)
                    }
                }
                .lvGlowPress()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}
