// LuminaVaultClient/LuminaVaultClient/Features/DailyReview/DailyReviewView.swift
//
// Daily review: every memory in today's resurface queue, each with why it is
// back and the same four answers as the Home card.
//
// It runs on Home's own `ResurfaceQueueViewModel`, not a copy of it, so an
// answer given here has already moved the Home card and its tile on by the
// time Back is tapped.

import LuminaVaultShared
import SwiftUI

struct DailyReviewView: View {
    let queue: ResurfaceQueueViewModel
    let memoryClient: any MemoryClientProtocol
    var spacesClient: (any SpacesClientProtocol)?

    @State private var openMemory: ResurfaceItemDTO?

    var body: some View {
        // No `NavigationStack` here: Home pushes this view, so owning one
        // would draw a second navigation bar under the first.
        List {
            content
        }
        .listStyle(.insetGrouped)
        .refreshable { await queue.load() }
        .navigationTitle("Daily review")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $openMemory) { item in
            MemoryDetailSheet(
                memoryID: item.memoryId,
                client: memoryClient,
                spacesClient: spacesClient
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch queue.phase {
        case .loading where queue.items.isEmpty:
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        case .failed(let message) where queue.items.isEmpty:
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .lvFont(.footnote)
                    .foregroundStyle(.secondary)
            }
        default:
            if queue.items.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nothing to revisit today",
                        systemImage: "checkmark.circle",
                        description: Text(queue.confirmation ?? "New memories come back here when they are worth another look.")
                    )
                }
            } else {
                Section {
                    ForEach(queue.items) { item in
                        ResurfaceCard(
                            item: item,
                            remaining: 0,
                            confirmation: nil,
                            isPending: queue.pendingMemoryID == item.memoryId,
                            errorMessage: nil,
                            onOpen: { openMemory = $0 },
                            onAction: { action, item in Task { await queue.perform(action, on: item) } },
                            onConfirmationShown: {},
                            showsHeader: false
                        )
                    }
                } footer: {
                    if let confirmation = queue.confirmation {
                        Label(confirmation, systemImage: "checkmark.circle.fill")
                    } else if let error = queue.actionError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                    }
                }
                .task(id: queue.confirmation) {
                    guard queue.confirmation != nil else { return }
                    try? await Task.sleep(for: .seconds(2.5))
                    guard !Task.isCancelled else { return }
                    queue.clearConfirmation()
                }
            }
        }
    }
}
