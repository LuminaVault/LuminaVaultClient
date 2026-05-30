// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ComposerBar.swift
//
// Pill composer for the AI chat. Leading attach (+) opens a file
// importer (txt / md / pdf — extracted client-side, see
// AttachmentTextExtractor). Trailing: hold-to-talk mic (gold pulse +
// inline waveform while recording) and a gold send arrow gated on
// `canSend`. While streaming, the mic/send pair is replaced by a stop
// control. Extracted from ChatView so the file stays focused.
import SwiftUI
import UniformTypeIdentifiers

struct ComposerBar: View {
    @Environment(\.lvPalette) private var palette
    @Binding var text: String
    let canSend: Bool
    let isStreaming: Bool
    /// Filename of the currently staged attachment, if any. Drives the
    /// chip shown above the field.
    let stagedAttachmentName: String?
    @Bindable var voice: VoiceModeController
    let onSend: () -> Void
    let onCancel: () -> Void
    /// Called with a picked file URL (security-scoped). The host extracts
    /// its text and stages it on the view model.
    let onAttach: (URL) -> Void
    let onClearAttachment: () -> Void

    @State private var showImporter = false

    private var allowedContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .pdf, .text]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        return types
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            if let stagedAttachmentName {
                ChatAttachmentChip(name: stagedAttachmentName, onRemove: onClearAttachment)
            }

            HStack(alignment: .center, spacing: LVSpacing.sm) {
                attachButton

                field

                Spacer(minLength: LVSpacing.xs)

                if isStreaming {
                    stopButton
                } else {
                    MicHoldButton(voice: voice)
                    sendButton
                }
            }
        }
        .padding(.horizontal, LVSpacing.base)
        .padding(.vertical, LVSpacing.md)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.card)
        .lvInnerGlow(cornerRadius: LVRadius.card, intensity: LVGlow.subtle)
        .padding(.horizontal, LVSpacing.lg)
        .padding(.vertical, LVSpacing.sm)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: canSend)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                onAttach(url)
            }
        }
    }

    private var attachButton: some View {
        Button {
            showImporter = true
        } label: {
            LVIconView(.plusCircleFill, size: 26, tint: palette.glowPrimary)
                .shadow(color: palette.glowPrimary.opacity(0.6), radius: 8)
        }
        .lvGlowPress()
        .disabled(voice.isRecording)
        .opacity(voice.isRecording ? 0.4 : 1)
        .accessibilityLabel("Attach a file")
    }

    private var field: some View {
        ZStack(alignment: .leading) {
            TextField("Ask Hermie anything…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 6)
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .tint(palette.glowPrimary)
                .submitLabel(.send)
                .onSubmit(onSend)
                .disabled(voice.isRecording)
                .opacity(voice.isRecording ? 0 : 1)

            if voice.isRecording {
                HStack(spacing: LVSpacing.sm) {
                    VoiceWaveformView(active: true)
                    Text(voice.liveTranscript.isEmpty ? "Listening…" : voice.liveTranscript)
                        .lvFont(.body)
                        .foregroundStyle(
                            voice.liveTranscript.isEmpty
                                ? palette.textSecondary
                                : palette.textPrimary
                        )
                        .lineLimit(2)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: voice.isRecording)
    }

    private var stopButton: some View {
        Button(action: onCancel) {
            LVIconView(.stopCircleFill, size: 26, tint: palette.accent)
                .shadow(color: palette.accent.opacity(0.6), radius: 8)
        }
        .lvPulse(active: true)
        .accessibilityLabel("Stop")
    }

    private var sendButton: some View {
        Button(action: onSend) {
            LVIconView(.arrowUpCircleFill, size: 30, tint: palette.accent)
                .shadow(color: palette.accent.opacity(canSend ? 0.8 : 0), radius: 10)
        }
        .lvGlowPress()
        .disabled(!canSend)
        .opacity(canSend ? 1 : 0.5)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel("Send")
    }
}
