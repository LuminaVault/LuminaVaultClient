// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/JobProposalCard.swift
//
// Lumina Jobs P3 — when the chat classifier detects a recurring-job request,
// this card surfaces above the composer pre-filled from the proposal. Confirm
// creates the scheduled job (POST /v1/jobs); dismiss hides it.

import LuminaVaultShared
import SwiftUI

struct JobProposalCard: View {
    let proposal: JobProposalDTO
    let onCreate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        MuseProposalCard(
            caption: "Standing task",
            title: proposal.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Make this a Job?",
            schedule: proposal.scheduleHuman ?? proposal.cron,
            spec: proposal.spec,
            confirmLabel: "Confirm",
            dismissHint: "Dismiss job suggestion",
            onConfirm: onCreate,
            onDismiss: onDismiss
        )
    }
}
