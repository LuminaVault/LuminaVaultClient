// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/JobProposalCard.swift
//
// Lumina Jobs P3 — when the chat classifier detects a recurring-job request,
// this card surfaces above the composer pre-filled from the proposal. Confirm
// creates the scheduled job (POST /v1/jobs); dismiss hides it.

import LuminaVaultShared
import SwiftUI

struct JobProposalCard: View {
    @Environment(\.lvPalette) private var palette
    let proposal: JobProposalDTO
    let onCreate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.glowPrimary)
                Text("Make this a Job?")
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
                if let schedule = proposal.scheduleHuman ?? proposal.cron {
                    chip(systemImage: "clock", text: schedule)
                }
                if let domain = proposal.domain {
                    chip(systemImage: "tag", text: domain.capitalized)
                }
            }

            if let spec = proposal.spec, !spec.isEmpty {
                Text(spec)
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
                    Text("Create Job")
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
