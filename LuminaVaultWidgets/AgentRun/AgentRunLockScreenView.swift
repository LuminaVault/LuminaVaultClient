//
//  AgentRunLockScreenView.swift
//  LuminaVaultWidgets
//

import SwiftUI

struct AgentRunLockScreenView: View {
    let agentName: String
    let state: AgentRunAttributes.ContentState
    var isStale = false
    var avatar: Image = Image("HermieAvatar")

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            MuseActivityAvatar(stage: state.stage, size: 48, avatar: avatar)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    AgentRunNameStatus(
                        agentName: agentName,
                        status: AgentRunActivityCopy.status(state, isStale: isStale)
                    )
                    AgentRunStageGlyph(state: state)
                        .font(.subheadline)
                }
                AgentRunTitlePill(title: state.title)
            }
        }
        .padding(16)
        .background(MuseActivityPalette.canvas)
    }
}
