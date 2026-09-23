// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/MuseProposalCard.swift
//
// The Muse contract's standing-task card look, shared by the job and
// reminder proposals: an agent-bubble-coloured card with a small uppercase
// caption, the title, the human schedule, one spec line, and two buttons —
// "Not now" and the confirm action.
//
// Deliberately quiet: no glass, no gold ring, no glow. It reads as something
// Hermie said, not as a banner.

import SwiftUI

struct MuseProposalCard: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    /// 11pt uppercase line above the title: "Standing task", "Reminder".
    let caption: String
    let title: String
    var schedule: String?
    var spec: String?
    let confirmLabel: String
    let dismissHint: String
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    private var muse: LVMuseColors { palette.muse(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text(caption)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(muse.textSecondary)

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(muse.text)

            if let schedule, !schedule.isEmpty {
                Label(schedule, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(muse.text)
            }

            if let spec, !spec.isEmpty {
                Text(spec)
                    .font(.footnote)
                    .foregroundStyle(muse.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: LVSpacing.sm) {
                Spacer(minLength: 0)
                Button("Not now", action: onDismiss)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(muse.text)
                    .padding(.horizontal, LVSpacing.base)
                    .frame(minHeight: LVSize.tapTarget)
                    .background(Capsule().fill(muse.pill))
                    .buttonStyle(.plain)
                    .accessibilityHint(dismissHint)
                Button(action: onConfirm) {
                    Text(confirmLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(muse.userText)
                        .padding(.horizontal, LVSpacing.base)
                        .frame(minHeight: LVSize.tapTarget)
                        .background(Capsule().fill(muse.userBubble))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, LVSpacing.xs)
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LVMuse.cardRadius, style: .continuous)
                .fill(muse.agentBubble)
        )
        .museBubbleWidth(LVMuse.agentBubbleWidth, alignment: .leading)
    }
}
