// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ReminderProposalCard.swift
//
// HER-55 — when the chat classifier detects a "remind me…" request, this card
// surfaces above the composer pre-filled from the proposal. Confirm creates the
// reminder (POST /v1/reminders); dismiss hides it. Mirrors JobProposalCard.

import LuminaVaultShared
import SwiftUI

struct ReminderProposalCard: View {
    @Environment(\.lvPalette) private var palette
    let proposal: ReminderProposalDTO
    let onCreate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.glowPrimary)
                Text("Set a reminder?")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }

            if let title = proposal.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }

            HStack(spacing: 8) {
                if let schedule = scheduleLabel {
                    chip(systemImage: "clock", text: schedule)
                }
                if proposal.recurrenceCron != nil {
                    chip(systemImage: "repeat", text: "Recurring")
                }
            }

            if let body = proposal.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button("Not now", action: onDismiss)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button(action: onCreate) {
                    Text("Remind me")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [palette.glowPrimary, palette.secondary],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        )
                        .shadow(color: palette.glowPrimary.opacity(0.5), radius: 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.8)
        .lvAuroraGoldRing(cornerRadius: LVRadius.card)
    }

    /// Prefer the human schedule string; otherwise format the absolute time.
    private var scheduleLabel: String? {
        if let human = proposal.scheduleHuman, !human.isEmpty { return human }
        guard let fireAt = proposal.fireAt else { return nil }
        return fireAt.formatted(.dateTime.month().day().hour().minute())
    }

    private func chip(systemImage: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(palette.glowPrimary)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(palette.glowPrimary.opacity(0.12)))
        .overlay(Capsule().stroke(palette.glowPrimary.opacity(0.35), lineWidth: 1))
    }
}
