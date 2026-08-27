// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ChatAttachmentChip.swift
//
// Staged-file chip shown above the composer field once a file is picked
// and its text extracted. Filename + remove button; the extracted text
// rides into the next message's content (see AttachmentTextExtractor).
import SwiftUI

struct ChatAttachmentChip: View {
    @Environment(\.lvPalette) private var palette
    let name: String
    /// Leading glyph. Defaults to the document icon; the edit-and-resend chip
    /// passes `.pencil` so it reads as a different kind of attachment while
    /// keeping the shape and the remove affordance identical.
    var icon: LVIcon = .docText
    var removeLabel: String = "Remove attachment"
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: LVSpacing.xs) {
            LVIconView(icon, size: 14, tint: palette.glowPrimary)

            Text(name)
                .lvFont(.microTag)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button(action: onRemove) {
                LVIconView(.xmarkCircleFill, size: 16, tint: palette.textSecondary)
                    .frame(minWidth: LVSize.tapTarget, minHeight: LVSize.tapTarget)
                    .contentShape(.rect)
            }
            .lvGlowPress()
            .accessibilityLabel(removeLabel)
        }
        .padding(.horizontal, LVSpacing.sm)
        .padding(.vertical, LVSpacing.xs)
        .background(Capsule().fill(palette.surface))
        .overlay {
            Capsule().stroke(palette.glowPrimary.opacity(0.3), lineWidth: 1)
        }
    }
}
