// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ChatAttachmentChip.swift
//
// Staged-file chip shown above the composer field once a file is picked
// and its text extracted. Filename + remove button; the extracted text
// rides into the next message's content (see AttachmentTextExtractor).
import SwiftUI

struct ChatAttachmentChip: View {
    @Environment(\.lvPalette) private var palette
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: LVSpacing.xs) {
            LVIconView(.docText, size: 14, tint: palette.glowPrimary)

            Text(name)
                .lvFont(.microTag)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button(action: onRemove) {
                LVIconView(.xmarkCircleFill, size: 16, tint: palette.textSecondary)
            }
            .lvGlowPress()
            .accessibilityLabel("Remove attachment")
        }
        .padding(.horizontal, LVSpacing.sm)
        .padding(.vertical, LVSpacing.xs)
        .background(Capsule().fill(palette.surface))
        .overlay {
            Capsule().stroke(palette.glowPrimary.opacity(0.3), lineWidth: 1)
        }
    }
}
