// LuminaVaultClient/LuminaVaultClient/Features/Think/Components/FollowUpChipsView.swift
// HER-37: chips that appear under an insight card. Scaffold uses
// hardcoded labels passed in from the ViewModel — HER-37b will swap in
// follow-ups derived from the active insight's source memories.
import SwiftUI

struct FollowUpChipsView: View {
    let chips: [String]
    var onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        onTap(chip)
                    } label: {
                        Text(chip)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.lvCyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.lvCyan.opacity(0.12))
                            )
                            .overlay(
                                Capsule().stroke(Color.lvCyan.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
