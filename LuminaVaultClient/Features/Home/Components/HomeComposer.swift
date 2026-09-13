// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/HomeComposer.swift
//
// The first thing on the first screen: one field that takes whatever you have.
//
// One field rather than a mode picker. Paste a link and it is saved as a link;
// type a thought and it is saved as a note. The controls underneath are only
// for the inputs a text field genuinely cannot take.

import SwiftUI

struct HomeComposer: View {
    @Environment(\.lvPalette) private var palette

    @Binding var text: String
    @FocusState.Binding var focused: Bool

    let isSaving: Bool
    /// Non-nil when the field holds nothing but a URL.
    let detectedLink: URL?
    let canSave: Bool
    let isRecording: Bool
    let onSubmit: () -> Void
    let onVoice: () -> Void
    let onPhotos: () -> Void
    let onFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            TextField("What do you want to remember?", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lvFont(.body)
                .lineLimit(1...6)
                .focused($focused)
                .disabled(isSaving)
                .accessibilityLabel("What do you want to remember?")

            if let link = detectedLink {
                linkChip(link)
            }

            HStack(spacing: LVSpacing.xs) {
                Button(action: onVoice) {
                    LVIconView(
                        isRecording ? .stopCircleFill : .micFill,
                        size: 18,
                        tint: isRecording ? palette.glowPrimary : palette.textSecondary,
                        label: isRecording ? "Stop recording" : "Record a voice note"
                    )
                    .frame(minWidth: LVSize.tapTarget, minHeight: LVSize.tapTarget)
                    .contentShape(.rect)
                }
                .disabled(isSaving)

                affordance(.photoOnRectangleAngled, label: "Add a photo", action: onPhotos)
                affordance(.paperclip, label: "Add a file", action: onFiles)

                Spacer(minLength: LVSpacing.sm)

                Button(action: onSubmit) {
                    LVIconView(
                        .arrowUpCircleFill,
                        size: 28,
                        tint: canSave ? palette.primary : palette.textSecondary.opacity(0.4),
                        label: "Save"
                    )
                }
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, LVSpacing.base - 2)
        .padding(.vertical, LVSpacing.md)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.55)
    }

    /// The page has not been fetched yet, so the host is the only honest thing
    /// to show. The real title arrives when the server finishes enriching.
    private func linkChip(_ link: URL) -> some View {
        HStack(spacing: LVSpacing.sm) {
            LVIconView(.linkCircle, size: 16, tint: palette.glowPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.host ?? link.absoluteString)
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Saved as a link")
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LVSpacing.md)
        .padding(.vertical, LVSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .fill(palette.surface.opacity(0.5))
        )
    }

    private func affordance(_ icon: LVIcon, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LVIconView(icon, size: 18, tint: palette.textSecondary, label: label)
                .frame(minWidth: LVSize.tapTarget, minHeight: LVSize.tapTarget)
                .contentShape(.rect)
        }
        .disabled(isSaving)
    }
}
