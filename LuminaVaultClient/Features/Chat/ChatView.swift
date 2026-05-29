// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatView.swift
//
// HER-269 — multi-turn SSE chat surface. Drops into any NavigationStack
// host (Think tab, dev menu, etc.). Composer pinned via
// `.safeAreaInset(edge: .bottom)`. Auto-scrolls to the live pending
// bubble as tokens arrive.
import SwiftUI

struct ChatView: View {
    @Environment(\.lvPalette) private var palette
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
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                // Deep cosmic gradients
                RadialGradient(
                    colors: [palette.glowPrimary.opacity(0.12), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 500
                ).ignoresSafeArea()
                
                ScrollView {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        EmptyStateHero(
                            mascotState: viewModel.mascotState,
                            headline: emptyHeadline,
                            supporting: emptySupporting,
                            suggestions: emptyStateSuggestions,
                            onSuggestion: { viewModel.sendSuggestion($0) },
                        )
                        .padding(.horizontal, LVSpacing.lg)
                        .padding(.top, LVSpacing.xl)
                    } else {
                        LazyVStack(alignment: .leading, spacing: LVSpacing.base) {
                            // Header for active chat (compact view)
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
                                    text: viewModel.pendingAssistant,
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
                        .padding(.vertical, LVSpacing.lg)
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
            .safeAreaInset(edge: .top) {
                LuminaHeader(title: emptyHeadline, mascotState: viewModel.mascotState)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
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

                ComposerBar(
                    text: $viewModel.composer,
                    canSend: viewModel.canSend,
                    isStreaming: viewModel.isStreaming,
                    voice: viewModel.voice,
                    onSend: {
                        composerFocused = false
                        viewModel.send()
                    },
                    onCancel: viewModel.cancel,
                )
                .focused($composerFocused)
            }
            .padding(.bottom, bottomPadding)
            .background(.clear)
        }
    }

    private static let pendingAnchor = "lv.chat.pending"
}

// MARK: - Empty state

private struct EmptyStateHero: View {
    @Environment(\.lvPalette) private var palette
    let mascotState: HermieMascotState
    let headline: String
    let supporting: String
    let suggestions: [String]
    let onSuggestion: (String) -> Void

    private let mascotSize: CGFloat = 240

    var body: some View {
        VStack(spacing: LVSpacing.xxl) {
            // Header row
            HStack(alignment: .top) {
                Text(headline)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [palette.glowPrimary, palette.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: palette.glowPrimary.opacity(0.75), radius: 14)

                Spacer()

                LVIconView(.personCircleFill, size: 32, tint: palette.glowPrimary, weight: .light)
                    .shadow(color: palette.glowPrimary.opacity(0.6), radius: 8)
            }

            // HER-302 — mascot with halo + sparkle dust.
            ZStack {
                LVHaloBackdrop(focalSize: mascotSize, intensity: LVGlow.hero, particleCount: 12)
                    .frame(width: mascotSize * 2.2, height: mascotSize * 2.2)
                    .allowsHitTesting(false)

                SparkleField(density: 14, maxRadius: 1.4)
                    .frame(width: mascotSize * 1.6, height: mascotSize * 1.6)
                    .opacity(0.5)
                    .blendMode(.screen)
                    .allowsHitTesting(false)

                HermieMascotView(state: mascotState, size: mascotSize,
                                 fallbackImageName: "OnboardingMascot")
                    .shadow(color: palette.glowPrimary.opacity(0.55), radius: 40)
            }
            .frame(maxWidth: .infinity)

            if !supporting.isEmpty {
                Text(supporting)
                    .lvFont(.callout)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, LVSpacing.lg)
            }

            if !suggestions.isEmpty {
                VStack(alignment: .trailing, spacing: LVSpacing.md) {
                    ForEach(suggestions.prefix(3), id: \.self) { suggestion in
                        Button {
                            onSuggestion(suggestion)
                        } label: {
                            Text(suggestion)
                                .lvFont(.bodyEmphasis)
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, LVSpacing.base)
                                .padding(.vertical, LVSpacing.md)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                        .background(
                            Capsule().fill(palette.surface)
                        )
                        .lvGlowStroke(cornerRadius: LVRadius.pill, intensity: LVGlow.subtle)
                        .lvGlowPress()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
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
/// failures (mic denied, no speech detected, recognizer unavailable).
/// Auto-decays via `VoiceModeController.errorMessage` after 3.5s.
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

// MARK: - Composer

private struct ComposerBar: View {
    @Environment(\.lvPalette) private var palette
    @Binding var text: String
    let canSend: Bool
    let isStreaming: Bool
    @Bindable var voice: VoiceModeController
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: LVSpacing.md) {
            LVIconView(.magnifyingglass, size: 18, tint: palette.glowPrimary, weight: .bold)

            ZStack(alignment: .leading) {
                TextField("Ask Hermie anything...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 6)
                    .lvFont(.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(palette.glowPrimary)
                    .submitLabel(.send)
                    .disabled(voice.isRecording)
                    .opacity(voice.isRecording ? 0 : 1)
                if voice.isRecording {
                    Text(voice.liveTranscript.isEmpty ? "Listening…" : voice.liveTranscript)
                        .lvFont(.body)
                        .foregroundStyle(
                            voice.liveTranscript.isEmpty
                                ? palette.textSecondary
                                : palette.textPrimary
                        )
                        .lineLimit(3)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: voice.isRecording)

            Spacer()

            if isStreaming {
                Button(action: onCancel) {
                    LVIconView(.stopCircleFill, size: 24, tint: palette.accent)
                        .shadow(color: palette.accent.opacity(0.6), radius: 8)
                }
                .lvPulse(active: true)
            } else {
                MicHoldButton(voice: voice)

                // Send button stays visible whenever we're not streaming so
                // the affordance is always discoverable; it dims + disables
                // until there's sendable text (canSend).
                Button(action: onSend) {
                    LVIconView(.arrowUpCircleFill, size: 28, tint: palette.glowPrimary)
                        .shadow(color: palette.glowPrimary.opacity(canSend ? 0.75 : 0), radius: 10)
                }
                .lvGlowPress()
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.35)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, LVSpacing.base)
        .padding(.vertical, LVSpacing.md)
        .lvGlassCard(cornerRadius: LVRadius.lg, intensity: LVGlow.card)
        .lvInnerGlow(cornerRadius: LVRadius.lg, intensity: LVGlow.subtle)
        .padding(.horizontal, LVSpacing.lg)
        .padding(.vertical, LVSpacing.md)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: canSend && !text.isEmpty)
    }
}
