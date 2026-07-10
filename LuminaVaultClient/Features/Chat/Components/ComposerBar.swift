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
    /// When true, the Return key sends; when false it inserts a newline and the
    /// user sends with the button (chat preference `sendOnReturn`).
    var sendOnReturn: Bool = false
    /// Names of the currently staged references. Drives the chips shown
    /// above the field.
    let referenceNames: [String]
    @Bindable var voice: VoiceModeController
    let onSend: () -> Void
    let onCancel: () -> Void
    /// Called with a picked file URL (security-scoped). The host extracts
    /// its text and stages it on the view model.
    let onAttach: (URL) -> Void
    /// Removes the staged reference at the given index.
    let onRemoveReference: (Int) -> Void
    /// Opens the vault-note `@`-reference picker on the host.
    let onPickNote: () -> Void
    /// Opens the photo picker on the host (image is uploaded to the vault).
    let onPickPhoto: () -> Void
    /// Opens the add-link prompt on the host.
    let onAddLink: () -> Void

    @State private var showImporter = false

    private var allowedContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .pdf, .text]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        return types
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            if !referenceNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LVSpacing.xs) {
                        ForEach(Array(referenceNames.enumerated()), id: \.offset) { index, name in
                            ChatAttachmentChip(name: name, onRemove: { onRemoveReference(index) })
                        }
                    }
                }
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
        Menu {
            Button {
                showImporter = true
            } label: {
                Label("Attach a file", systemImage: "doc")
            }
            Button {
                onPickNote()
            } label: {
                Label("Reference a note", systemImage: "text.document")
            }
            Button {
                onPickPhoto()
            } label: {
                Label("Add a photo", systemImage: "photo")
            }
            Button {
                onAddLink()
            } label: {
                Label("Add a link", systemImage: "link")
            }
        } label: {
            LVIconView(.plusCircleFill, size: 26, tint: palette.glowPrimary)
                .shadow(color: palette.glowPrimary.opacity(0.6), radius: 8)
        }
        .lvGlowPress()
        .disabled(voice.isRecording)
        .opacity(voice.isRecording ? 0.4 : 1)
        .accessibilityLabel("Add context")
    }

    private var field: some View {
        ZStack(alignment: .leading) {
            TextField("Ask Hermie anything…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 6)
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .tint(palette.glowPrimary)
                .submitLabel(sendOnReturn ? .send : .return)
                .onSubmit { if sendOnReturn { onSend() } }
                .onKeyPress(.return, phases: .down, action: handleReturnKey)
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

    /// Hardware-keyboard behavior mirrors desktop chat apps. Return follows
    /// the preference; Shift+Return deliberately performs the inverse.
    private func handleReturnKey(_ press: KeyPress) -> KeyPress.Result {
        let isShiftReturn = press.modifiers.contains(.shift)

        if isShiftReturn {
            if sendOnReturn {
                text.append("\n")
            } else {
                onSend()
            }
            return .handled
        }

        guard sendOnReturn else { return .ignored }
        onSend()
        return .handled
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
