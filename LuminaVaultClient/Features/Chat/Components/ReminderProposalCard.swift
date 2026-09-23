// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ReminderProposalCard.swift
//
// HER-55 — when the chat classifier detects a "remind me…" request, this card
// surfaces above the composer pre-filled from the proposal. Confirm creates the
// reminder (POST /v1/reminders); dismiss hides it. Mirrors JobProposalCard.

import LuminaVaultShared
import SwiftUI

struct ReminderProposalCard: View {
    let proposal: ReminderProposalDTO
    let onCreate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        MuseProposalCard(
            caption: "Reminder",
            title: proposal.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Set a reminder?",
            schedule: scheduleLabel,
            spec: proposal.body,
            confirmLabel: "Remind me",
            dismissHint: "Dismiss reminder suggestion",
            onConfirm: onCreate,
            onDismiss: onDismiss
        )
    }

    /// Prefer the human schedule string; otherwise format the absolute time.
    private var scheduleLabel: String? {
        if let human = proposal.scheduleHuman, !human.isEmpty { return human }
        guard let fireAt = proposal.fireAt else { return nil }
        return fireAt.formatted(.dateTime.month().day().hour().minute())
    }
}
