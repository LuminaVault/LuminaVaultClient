// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/HomeDailyPostRow.swift
//
// Home "Today": today's AI Daily Post from the Community board — its title
// and the AI caption. The whole row opens the board, where the post is
// pinned on top. The caller hides it when the board is off or no post yet.

import LuminaVaultShared
import SwiftUI

struct HomeDailyPostRow: View {
    let post: CommunityPostDTO
    let onOpen: () -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: LVSpacing.md) {
                Image(systemName: "person.3")
                    .font(.title3)
                    .foregroundStyle(palette.primary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LVSpacing.xs) {
                    CommunityAIBadge(
                        text: CommunityPresentation.aiLabel(post) ?? CommunityPresentation.aiFallbackLabel
                    )
                    Text(post.title ?? post.body)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .lvFont(.footnote)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, LVSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(CommunityPresentation.aiLabel(post) ?? CommunityPresentation.aiFallbackLabel). \(post.title ?? post.body)"
        )
        .accessibilityHint("Opens the Community board")
        .accessibilityAddTraits(.isButton)
    }
}
