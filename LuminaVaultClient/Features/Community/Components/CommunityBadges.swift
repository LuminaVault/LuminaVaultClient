// LuminaVaultClient/LuminaVaultClient/Features/Community/Components/CommunityBadges.swift
//
// The two small captions a post can carry. The AI one copies the proactive
// chat caption (`ProactiveCaptionView`): 11pt semibold, uppercase, tracked
// out — the same voice for "the app wrote this" everywhere.

import LuminaVaultShared
import SwiftUI

/// "AI-generated · Daily Post", verbatim from the server's `aiLabel`.
struct CommunityAIBadge: View {
    let text: String

    @Environment(\.lvPalette) private var palette

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "sparkles")
                .imageScale(.small)
        }
        .labelStyle(.titleAndIcon)
        .font(.system(size: 11, weight: .semibold))
        .textCase(.uppercase)
        .kerning(0.8)
        .foregroundStyle(palette.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Shown on the author's own post while moderation holds it.
struct CommunityPendingBadge: View {
    var body: some View {
        Label("Awaiting review", systemImage: "clock")
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.8)
            .foregroundStyle(.orange)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Awaiting review. Only you can see this post until it is approved.")
    }
}

/// Byline: display name, @handle, relative time.
struct CommunityByline: View {
    let post: CommunityPostDTO

    var body: some View {
        HStack(spacing: LVSpacing.xs) {
            Text(CommunityPresentation.authorName(post))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let handle = CommunityPresentation.authorHandle(post) {
                Text(handle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("·").foregroundStyle(.tertiary)
            Text(post.createdAt, format: .relative(presentation: .named))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// The captions under a byline, if any.
struct CommunityPostCaptions: View {
    let post: CommunityPostDTO

    var body: some View {
        if let label = CommunityPresentation.aiLabel(post) {
            CommunityAIBadge(text: label)
        }
        if CommunityPresentation.showsPendingBadge(post) {
            CommunityPendingBadge()
        }
    }
}
