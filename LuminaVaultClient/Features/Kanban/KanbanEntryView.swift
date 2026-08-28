// LuminaVaultClient/LuminaVaultClient/Features/Kanban/KanbanEntryView.swift
//
// C6 — Navigation entry-point for the Kanban feature.
// Resolves the user's default board by calling `listBoards()` and taking
// `.first` (the server auto-creates one per tenant). Shows a ProgressView
// until the board id is available, then pushes KanbanBoardView.

import SwiftUI
import LuminaVaultShared

struct KanbanEntryView: View {
    @Environment(\.lvPalette) private var palette

    let client: any KanbanClientProtocol

    @State private var boardID: UUID?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let boardID {
                // The board owns its own `.lvBackground()`.
                KanbanBoardView(boardID: boardID, client: client)
            } else {
                // Both pre-board states used to paint `Color.black.opacity(0.92)`
                // over the safe area. That is not a background, it is a black
                // scrim: in Light mode it turned the screen near-black under
                // dark body text, and in Dark mode it occluded the themed
                // backdrop every other screen shows. `.lvBackground()` is the
                // one owner of the base fill and aurora — the same correction
                // Stage 1 made on Home and Settings in 735b5d4.
                placeholder.lvBackground()
            }
        }
        .task { await loadBoard() }
    }

    /// Loading and failure share one frame so the backdrop is applied once.
    @ViewBuilder private var placeholder: some View {
        if isLoading {
            ProgressView("Loading board…")
                .tint(palette.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: LVSpacing.base) {
                // `.yellow` is a fixed sRGB yellow, not a system semantic
                // colour — on the Light backdrop it all but vanished. The
                // palette's `accent` is the warning/highlight signal and has
                // a darkened Light variant in all three branded themes.
                LVIconView(
                    .exclamationmarkTriangle,
                    size: LVSize.rowGlyph,
                    tint: palette.accent,
                    weight: .semibold
                )
                Text(errorMessage ?? "No board found.")
                    .font(LVTypography.callout.font)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await loadBoard() } }
                    .tint(palette.primary)
            }
            .padding(.horizontal, LVSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadBoard() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let boards = try await client.listBoards()
            if let first = boards.first {
                boardID = first.id
            } else {
                errorMessage = "No boards available."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
