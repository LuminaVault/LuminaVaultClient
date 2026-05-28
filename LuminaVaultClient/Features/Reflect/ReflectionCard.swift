// LuminaVaultClient/LuminaVaultClient/Features/Reflect/ReflectSkillCard.swift
//
// HER-194 — single tile for a Reflect skill. Wraps the shared
// `SciFiCardView` so the visual treatment matches other glass cards in
// the app.

import SwiftUI

struct ReflectSkillCard: View {
    let skill: ReflectionSkill
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            SciFiCardView(
                icon: skill.iconSystemName,
                title: skill.title,
                subtitle: skill.subtitle,
                color: nil,
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(skill.title) — \(skill.subtitle)")
    }
}
