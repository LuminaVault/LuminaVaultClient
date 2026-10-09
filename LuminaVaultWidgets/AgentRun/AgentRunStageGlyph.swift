//
//  AgentRunStageGlyph.swift
//  LuminaVaultWidgets
//

import SwiftUI

struct AgentRunStageGlyph: View {
    let state: AgentRunAttributes.ContentState
    /// Read by VoiceOver where the glyph stands in for the status line (the
    /// compact island). Elsewhere the status text is beside it, so the glyph
    /// stays hidden.
    var spokenStatus: String?

    var body: some View {
        Image(systemName: AgentRunActivityCopy.glyph(state))
            .fontWeight(.semibold)
            .foregroundStyle(state.stage == .failed ? MuseActivityPalette.snag : MuseActivityPalette.accent)
            .dynamicTypeSize(...MuseActivityPalette.maxTypeSize)
            .accessibilityHidden(spokenStatus == nil)
            .accessibilityLabel(spokenStatus ?? "")
    }
}
