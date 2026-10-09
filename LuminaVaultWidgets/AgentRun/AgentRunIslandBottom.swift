//
//  AgentRunIslandBottom.swift
//  LuminaVaultWidgets
//

import SwiftUI

struct AgentRunIslandBottom: View {
    let state: AgentRunAttributes.ContentState

    var body: some View {
        AgentRunTitlePill(title: state.title)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }
}
