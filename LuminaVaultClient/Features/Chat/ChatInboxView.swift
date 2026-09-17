// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatInboxView.swift
//
// The AI tab's root list. The navigation title and the single "New chat"
// action belong to the host's navigation bar, so there is no in-list header
// here — two titles and two "+" buttons on one screen was the bug.
import SwiftUI

struct ChatInboxView: View {
    @Environment(\.lvPalette) private var palette
    @State private var viewModel: ChatInboxViewModel

    let onOpen: (UUID) -> Void
    let onNewChat: () -> Void

    init(
        client: any ChatExperienceClientProtocol,
        conversationsClient: any ConversationsClientProtocol,
        onOpen: @escaping (UUID) -> Void,
        onNewChat: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: ChatInboxViewModel(
            client: client,
            conversationsClient: conversationsClient
        ))
        self.onOpen = onOpen
        self.onNewChat = onNewChat
    }

    var body: some View {
        List {
            Section {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if viewModel.items.isEmpty, let error = viewModel.errorMessage {
                    // A failed load must never render as "No chats yet" — that
                    // told users with full histories their chats were gone.
                    failureState(error)
                } else if viewModel.items.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.items) { item in
                        Button {
                            onOpen(item.id)
                        } label: {
                            ChatInboxRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(item) }
                            } label: {
                                Label("Delete", systemImage: LVIcon.trash.sfSymbol)
                            }
                        }
                    }
                }
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
    }

    /// Shown when the inbox fetch failed and we have nothing cached. Distinct
    /// from `emptyState`: "we couldn't load your chats" is a very different
    /// claim from "you have no chats".
    private func failureState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            LVIconView(.exclamationmarkTriangleFill, size: 26, tint: palette.accent)
            Text("Couldn't load your chats")
                .font(LVTypography.bodyEmphasis.font)
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(LVTypography.callout.font)
                .foregroundStyle(palette.textSecondary)
            Button("Try again") { Task { await viewModel.load() } }
                .buttonStyle(.borderedProminent)
                .padding(.top, LVSpacing.xs)
        }
        .padding(.vertical, LVSpacing.md)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            LVIconView(.bubbleLeftAndTextBubbleRight, size: 26, tint: palette.glowPrimary)
            Text("No chats yet")
                .font(LVTypography.bodyEmphasis.font)
                .foregroundStyle(palette.textPrimary)
            Text("Start a chat and it will appear here with its latest activity.")
                .font(LVTypography.callout.font)
                .foregroundStyle(palette.textSecondary)
            Button("New Chat", action: onNewChat)
                .buttonStyle(.borderedProminent)
                .padding(.top, LVSpacing.xs)
        }
        .padding(.vertical, LVSpacing.md)
    }
}

/// A stock inset-grouped row: title, preview, and the two facts worth
/// knowing about a thread. No leading glyph and no source pill — every row
/// in a single-source inbox carries the same ones, so they were decoration
/// that pushed the words that differ off the line.
private struct ChatInboxRow: View {
    let item: ChatInboxItemDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(ChatInboxDisplay.title(for: item))
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(item.lastMessageAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !item.preview.isEmpty {
                Text(item.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text("^[\(item.messageCount) message](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
