// LuminaVaultClient/LuminaVaultClient/Features/Community/Components/CommunityPostRow.swift
//
// A thread in the board list, and the pinned Daily Post card above it.

import LuminaVaultShared
import SwiftUI

struct CommunityPostRow: View {
    let post: CommunityPostDTO

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            CommunityByline(post: post)
            CommunityPostCaptions(post: post)
            if let title = post.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
            }
            Text(post.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Label("\(post.replyCount)", systemImage: "bubble.left")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(post.replyCount == 1 ? "1 reply" : "\(post.replyCount) replies")
        }
        .padding(.vertical, LVSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// Today's AI Daily Post, pinned on top of the board.
struct CommunityDailyPostCard: View {
    let post: CommunityPostDTO

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            HStack {
                CommunityAIBadge(text: CommunityPresentation.aiLabel(post) ?? CommunityPresentation.aiFallbackLabel)
                Spacer(minLength: 0)
                Image(systemName: "pin.fill")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            if let title = post.title, !title.isEmpty {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
            }
            Text(post.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            HStack(spacing: LVSpacing.xs) {
                Text(CommunityPresentation.aiAuthorName)
                    .font(.footnote.weight(.semibold))
                Text("·").foregroundStyle(.tertiary)
                Label("\(post.replyCount)", systemImage: "bubble.left")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, LVSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens today's Daily Post")
    }
}
