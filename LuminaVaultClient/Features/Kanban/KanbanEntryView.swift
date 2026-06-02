// LuminaVaultClient/LuminaVaultClient/Features/Kanban/KanbanEntryView.swift
//
// C6 — Navigation entry-point for the Kanban feature.
// Resolves the user's default board by calling `listBoards()` and taking
// `.first` (the server auto-creates one per tenant). Shows a ProgressView
// until the board id is available, then pushes KanbanBoardView.

import SwiftUI
import LuminaVaultShared

struct KanbanEntryView: View {
    let client: any KanbanClientProtocol

    @State private var boardID: UUID?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let boardID {
                KanbanBoardView(boardID: boardID, client: client)
            } else if isLoading {
                ProgressView("Loading board…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.92).ignoresSafeArea())
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(errorMessage ?? "No board found.")
                        .foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadBoard() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.92).ignoresSafeArea())
            }
        }
        .task { await loadBoard() }
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
