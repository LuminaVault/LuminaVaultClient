//
//  AgentRunTitlePill.swift
//  LuminaVaultWidgets
//

import SwiftUI

/// The prompt, in a `muse.pill`. The running tool is not repeated here: the
/// status line already says it ("is searching the web") and the stage glyph
/// shows it.
struct AgentRunTitlePill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(MuseActivityPalette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MuseActivityPalette.pill, in: .capsule)
            .dynamicTypeSize(...MuseActivityPalette.maxTypeSize)
    }
}
