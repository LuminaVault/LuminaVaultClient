// LuminaVaultClient/LuminaVaultClient/Features/Community/Components/CommunityPostActions.swift
//
// The per-post menu: Report and Block author for other members' posts,
// Delete for your own. Nothing for the AI's posts beyond what is shared.
// Used both as a context menu and inside a toolbar `Menu`.

import LuminaVaultShared
import SwiftUI

struct CommunityPostActions: View {
    let post: CommunityPostDTO
    let onReport: (CommunityPostDTO) -> Void
    let onBlock: (CommunityPostDTO) -> Void
    let onDelete: (CommunityPostDTO) -> Void

    var body: some View {
        if CommunityPresentation.canReport(post) {
            Button("Report post", systemImage: "flag") { onReport(post) }
        }
        if CommunityPresentation.canBlock(post) {
            Button("Block \(CommunityPresentation.authorName(post))", systemImage: "hand.raised", role: .destructive) {
                onBlock(post)
            }
        }
        if CommunityPresentation.canDelete(post) {
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(post) }
        }
    }

    static func hasActions(_ post: CommunityPostDTO) -> Bool {
        CommunityPresentation.canReport(post) || CommunityPresentation.canDelete(post)
    }
}

/// What a confirmation dialog is asking about.
enum CommunityPendingConfirmation: Identifiable {
    case block(CommunityPostDTO)
    case delete(CommunityPostDTO)

    var id: String {
        switch self {
        case .block(let post): "block-\(post.id)"
        case .delete(let post): "delete-\(post.id)"
        }
    }

    var title: String {
        switch self {
        case .block(let post): "Block \(CommunityPresentation.authorName(post))?"
        case .delete: "Delete this post?"
        }
    }

    var message: String {
        switch self {
        case .block: "You won't see their posts or replies anymore. They aren't told. You can unblock them from Blocked members."
        case .delete: "This can't be undone."
        }
    }

    var actionTitle: String {
        switch self {
        case .block: "Block"
        case .delete: "Delete"
        }
    }
}
