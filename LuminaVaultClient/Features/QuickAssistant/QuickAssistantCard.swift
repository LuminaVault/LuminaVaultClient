// LuminaVaultClient/LuminaVaultClient/Features/QuickAssistant/QuickAssistantCard.swift
//
// The floating card a long-press on the AI tab opens: a dim over the current
// screen, and a glowing card with a text field and a hold-to-talk mic. It is a
// transient modal rather than a place, which is why it may glow (DESIGN_SYSTEM
// §13.9) and why §13.8's ban on floating buttons does not cover it.
//
// `MainTabView` owns one `QuickAssistantSession` per opening and drops it on
// close, so a reopened card starts a new conversation and reads the current
// hybrid-execution settings.
import LuminaVaultShared
import SwiftUI

/// What a turn tells the server about where it was asked from.
struct QuickAssistantSendContext {
    let currentTab: String
    let activeSpaceID: UUID?
}

/// One opening of the card.
@Observable
@MainActor
final class QuickAssistantSession {
    let model: QuickAssistantModel
    let voice: VoiceModeController
    /// The question on show, typed or spoken.
    private(set) var prompt: String?

    private let synthesizer: any SpeechSynthesizing
    private let context: @MainActor () -> QuickAssistantSendContext
    private var isClosed = false

    init(
        model: QuickAssistantModel,
        voice: VoiceModeController,
        synthesizer: any SpeechSynthesizing,
        context: @escaping @MainActor () -> QuickAssistantSendContext
    ) {
        self.model = model
        self.voice = voice
        self.synthesizer = synthesizer
        self.context = context
        voice.onFinalTranscript = { [weak self] transcript in
            self?.send(transcript, viaVoice: true)
        }
    }

    func send(_ text: String, viaVoice: Bool) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isClosed, !content.isEmpty, model.phase != .sending else { return }
        prompt = content
        let context = context()
        let model = model
        // Held by the model, whose `reset()` cancels the turn.
        Task {
            await model.send(
                content,
                viaVoice: viaVoice,
                currentTab: context.currentTab,
                activeSpaceID: context.activeSpaceID
            )
        }
    }

    /// Holding the mic interrupts a reply being read out.
    func stopSpeaking() {
        synthesizer.stop()
    }

    /// Mic off with its pending transcript dropped, stream cancelled, speech
    /// stopped. Anything arriving afterwards finds nowhere to land.
    func close() {
        isClosed = true
        voice.shutDown()
        model.reset()
    }
}

struct QuickAssistantCard: View {
    let session: QuickAssistantSession
    let onClose: () -> Void
    let onOpenChat: (UUID) -> Void

    @Environment(\.lvPalette) private var palette
    @State private var text = ""
    @State private var replyHeight: CGFloat = 0
    @FocusState private var fieldFocused: Bool
    @AccessibilityFocusState private var fieldAccessibilityFocused: Bool

    private static let dimOpacity: Double = 0.5
    private static let cornerRadius: CGFloat = LVRadius.sheet
    private static let maxWidth: CGFloat = 560
    private static let maxReplyHeight: CGFloat = 260
    /// Above the home indicator, to clear the dimmed tab bar. The keyboard hides
    /// the bar, so with the field focused the card sits just above the keyboard.
    private static let tabBarClearance: CGFloat = 62

    private var model: QuickAssistantModel { session.model }
    private var voice: VoiceModeController { session.voice }
    private var isSending: Bool { model.phase == .sending }
    private var canSend: Bool {
        !isSending && !voice.isRecording && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(Self.dimOpacity)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)

            card
                .frame(maxWidth: Self.maxWidth)
                .padding(.horizontal, LVSpacing.base)
                .padding(.bottom, fieldFocused ? LVSpacing.md : Self.tabBarClearance)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .onAppear { fieldAccessibilityFocused = true }
        .onChange(of: voice.isRecording) { _, recording in
            if recording { session.stopSpeaking() }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            exchange

            // Task 10: action chips and confirm cards go here, from `model.actions`.

            if let message = voice.errorMessage {
                statusText(message)
            }

            composer

            if let conversationID = model.conversationID {
                openInChat(conversationID)
            }
        }
        .padding(LVSpacing.base)
        .lvGlassCard(cornerRadius: Self.cornerRadius, intensity: LVGlow.subtle, material: .regularMaterial)
        .background { QuickAssistantGlow(cornerRadius: Self.cornerRadius) }
        .lvAnimation(LVMotion.quick, value: model.conversationID)
        .lvAnimation(LVMotion.quick, value: voice.errorMessage)
    }

    // MARK: - Question and reply

    @ViewBuilder
    private var exchange: some View {
        if session.prompt != nil || model.phase != .idle {
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                if let prompt = session.prompt {
                    Text(prompt)
                        .lvFont(.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                if !model.reply.isEmpty {
                    reply
                }
                switch model.phase {
                case .idle:
                    EmptyView()
                case .sending:
                    if model.reply.isEmpty {
                        thinking
                    }
                case let .blocked(message), let .failed(message):
                    statusText(message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// As tall as the reply up to a limit, then it scrolls. Above the keyboard,
    /// in landscape especially, it also gives up height so the field stays visible.
    private var reply: some View {
        ScrollView {
            replyText
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { replyHeight = $0 }
        }
        .defaultScrollAnchor(.bottom)
        .scrollBounceBehavior(.basedOnSize)
        .frame(minHeight: 0, maxHeight: min(replyHeight, Self.maxReplyHeight))
    }

    private var replyText: some View {
        Text(formattedReply)
            .lvFont(.body)
            .foregroundStyle(palette.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var formattedReply: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: model.reply, options: options)) ?? AttributedString(model.reply)
    }

    private var thinking: some View {
        HStack(spacing: LVSpacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking…")
                .lvFont(.body)
                .foregroundStyle(palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func statusText(_ message: String) -> some View {
        Text(message)
            .lvFont(.footnote)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .center, spacing: LVSpacing.xs) {
            field
            MicHoldButton(voice: voice)
                .disabled(isSending)
            sendButton
        }
    }

    private var field: some View {
        ZStack(alignment: .leading) {
            TextField("Ask Lumina anything…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .tint(palette.glowPrimary)
                .submitLabel(.send)
                .focused($fieldFocused)
                .accessibilityFocused($fieldAccessibilityFocused)
                .accessibilityLabel("Ask Lumina")
                .onSubmit(sendTypedText)
                .disabled(voice.isRecording)
                .opacity(voice.isRecording ? 0 : 1)

            if voice.isRecording {
                HStack(spacing: LVSpacing.sm) {
                    VoiceWaveformView(active: true)
                    Text(voice.liveTranscript.isEmpty ? "Listening…" : voice.liveTranscript)
                        .lvFont(.body)
                        .foregroundStyle(
                            voice.liveTranscript.isEmpty ? palette.textSecondary : palette.textPrimary
                        )
                        .lineLimit(2)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: LVSize.tapTarget, alignment: .leading)
        .padding(.horizontal, LVSpacing.md)
        .background(palette.surfaceElevated, in: .rect(cornerRadius: LVRadius.md, style: .continuous))
        .lvAnimation(LVMotion.quick, value: voice.isRecording)
    }

    private var sendButton: some View {
        Button(action: sendTypedText) {
            LVIconView(.arrowUpCircleFill, size: 30, tint: palette.primary)
                .frame(minWidth: LVSize.tapTarget, minHeight: LVSize.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .opacity(canSend ? 1 : 0.4)
        .accessibilityLabel("Send")
    }

    private func sendTypedText() {
        guard canSend else { return }
        session.send(text, viaVoice: false)
        text = ""
    }

    // MARK: - Open in chat

    /// Unavailable during a turn: going to the chat closes the card, which would
    /// cancel the reply the user is going there to read.
    private func openInChat(_ conversationID: UUID) -> some View {
        Button("Open in chat") { onOpenChat(conversationID) }
            .buttonStyle(.plain)
            .lvFont(.footnote)
            .foregroundStyle(palette.primary)
            .frame(maxWidth: .infinity, minHeight: LVSize.tapTarget, alignment: .trailing)
            .contentShape(.rect)
            // Keeps the tap target without the height it would add to the card.
            .padding(.vertical, -LVSpacing.sm)
            .disabled(isSending)
            .opacity(isSending ? 0.4 : 1)
    }
}

/// The soft halo behind the card. It breathes slowly; with Reduce Motion on it
/// holds still at the midpoint (DESIGN_SYSTEM §8).
private struct QuickAssistantGlow: View {
    let cornerRadius: CGFloat

    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lvAmbientMotionEnabled) private var ambientMotionEnabled
    @State private var breathing = false

    private var animates: Bool { ambientMotionEnabled && !reduceMotion }

    private var opacity: Double {
        guard animates else { return 0.6 }
        return breathing ? 0.8 : 0.4
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                AngularGradient(
                    colors: [palette.glowPrimary, palette.glowSecondary, palette.accent, palette.glowPrimary],
                    center: .center
                )
            )
            .blur(radius: 18)
            .opacity(opacity)
            .lvRepeatingAnimation(LVMotion.ambient.repeatForever(autoreverses: true), value: breathing)
            .onAppear { breathing = true }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
