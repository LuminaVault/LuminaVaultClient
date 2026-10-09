//
//  AgentRunNameStatus.swift
//  LuminaVaultWidgets
//

import SwiftUI

struct AgentRunNameStatus: View {
    let agentName: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(agentName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MuseActivityPalette.text)
            Text(status)
                .font(.footnote)
                .foregroundStyle(MuseActivityPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...MuseActivityPalette.maxTypeSize)
        .accessibilityElement(children: .combine)
    }
}
