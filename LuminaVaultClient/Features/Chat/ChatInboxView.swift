// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatInboxView.swift
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
            } header: {
                header
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Chats")
                    .font(LVTypography.title.font.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .textCase(nil)
                Text("Recent threads, sources, and quick access.")
                    .font(LVTypography.caption.font)
                    .foregroundStyle(palette.textSecondary)
                    .textCase(nil)
            }
            Spacer()
            Button {
                onNewChat()
            } label: {
                LVIconView(.plusCircleFill, size: 24, tint: palette.glowPrimary)
            }
            .accessibilityLabel("New chat")
        }
        .padding(.top, LVSpacing.sm)
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

private struct ChatInboxRow: View {
    @Environment(\.lvPalette) private var palette
    let item: ChatInboxItemDTO

    var body: some View {
        HStack(alignment: .top, spacing: LVSpacing.base) {
            LVIconView(.bubbleLeftAndTextBubbleRight, size: 18, tint: palette.glowPrimary)
                .frame(width: LVSize.rowGlyph)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title.isEmpty ? "Untitled chat" : item.title)
                        .font(LVTypography.bodyEmphasis.font)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: LVSpacing.sm)
                    Text(item.lastMessageAt.formatted(.relative(presentation: .named)))
                        .font(LVTypography.caption.font)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                if !item.preview.isEmpty {
                    Text(item.preview)
                        .font(LVTypography.caption.font)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: LVSpacing.xs) {
                    if let source = item.sourceLabel, !source.isEmpty {
                        ChatInboxPill(source)
                    }
                    ChatInboxPill("\(item.messageCount) messages")
                }
            }
        }
        .padding(.vertical, LVSpacing.xs)
        .contentShape(Rectangle())
    }
}

private struct ChatInboxPill: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(LVTypography.caption.font.weight(.medium))
            .padding(.horizontal, LVSpacing.sm)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
            .foregroundStyle(.secondary)
    }
}
