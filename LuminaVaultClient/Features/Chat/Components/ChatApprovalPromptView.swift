// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ChatApprovalPromptView.swift
//
// The decision an escalated turn is blocked on, inline in the transcript.
//
// Inline rather than an alert: an alert would interrupt whatever the user is
// doing, and the command being approved needs to be read next to the steps
// that led to it. The run waits either way.

import LuminaVaultShared
import SwiftUI

struct ChatApprovalPromptView: View {
    let item: HermesRunTrailItem
    let isBusy: Bool
    let onRespond: (HermesApprovalChoice) -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            HStack(alignment: .top, spacing: LVSpacing.sm) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(palette.textSecondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: LVSpacing.sm) {
                choice(.once, "Allow once", prominent: true)
                choice(.session, "This session", prominent: true)
                Spacer(minLength: 0)
                choice(.deny, "Deny", prominent: false)
            }
        }
        .padding(LVSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .fill(palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                        .stroke(palette.accent.opacity(0.4), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Waiting for your approval")
    }

    private func choice(
        _ value: HermesApprovalChoice,
        _ label: String,
        prominent: Bool
    ) -> some View {
        Button {
            onRespond(value)
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, LVSpacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                        .fill(prominent ? palette.accent.opacity(0.18) : Color.clear)
                )
                .foregroundStyle(prominent ? palette.textPrimary : palette.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
    }
}
