// LuminaVaultClient/LuminaVaultClient/Features/Settings/Hermes/HermesMirrorCard.swift
//
// The counts, in the Hermes pane, where "Connected" is claimed.

import LuminaVaultShared
import SwiftUI

struct HermesMirrorCard: View {
    @Environment(\.lvPalette) private var palette
    @State var viewModel: HermesMirrorCardViewModel

    var body: some View {
        Section("Mirrored from your Hermes") {
            switch viewModel.state {
            case .loading:
                HStack {
                    ProgressView().tint(palette.primary)
                    Text("Reading…")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)
                }
            case let .failed(message):
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textPrimary)
                    Button("Try again") { Task { await viewModel.load() } }
                        .font(.system(size: 13, weight: .semibold))
                }
            case let .loaded(status):
                LabeledContent("Skills", value: "\(status.skillsCount)")
                LabeledContent("Jobs", value: "\(status.jobsCount)")
                LabeledContent("Sessions", value: "\(status.sessionsImported)")
                LabeledContent("Vault", value: status.vaultSummary)
                if let last = status.lastSyncAt {
                    LabeledContent("Last sync", value: last.formatted(.relative(presentation: .named)))
                }
                if let error = status.lastError, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.lvTextMuted)
                }
                // `lastStatus == .ok` with nothing mirrored is precisely how a
                // linked-but-unread Hermes looks, so call it out rather than
                // showing four zeroes under a green badge.
                if !status.hasMirroredAnything {
                    Text("Nothing has been mirrored yet. Sync to pull your skills, jobs and vault across.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.lvTextMuted)
                }
                if let message = viewModel.lastSyncMessage {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
            }

            Button {
                Task { await viewModel.sync() }
            } label: {
                if viewModel.isSyncing {
                    HStack {
                        ProgressView().tint(palette.primary)
                        Text("Syncing…")
                    }
                } else {
                    Text("Sync now")
                }
            }
            .disabled(viewModel.isSyncing)
        }
        .task { await viewModel.load() }
    }
}
