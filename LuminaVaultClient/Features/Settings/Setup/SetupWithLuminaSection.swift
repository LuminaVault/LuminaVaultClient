import SwiftUI
import UIKit

struct SetupWithLuminaSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.lvPalette) private var palette

    @State private var preset: SetupPreset = .claude
    @State private var custom = ""
    @State private var copied = false

    var onSend: () -> Void

    private var prompt: String {
        SetupPrompts.prompt(for: preset, custom: custom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            Text("Ask Lumina to connect Claude, Codex, Hermes, or anything else.")
                .font(LVTypography.footnote.font)
                .foregroundStyle(palette.textSecondary)

            HStack(spacing: 8) {
                ForEach(SetupPreset.allCases) { option in
                    Button(option.label) {
                        preset = option
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(
                            preset == option
                                ? palette.glowPrimary.opacity(0.18)
                                : Color.white.opacity(0.04)
                        )
                    )
                    .overlay(
                        Capsule().stroke(
                            preset == option ? palette.glowPrimary : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                    )
                    .foregroundStyle(preset == option ? palette.glowPrimary : palette.textSecondary)
                }
            }

            if preset == .anything {
                TextField("Describe the setup", text: $custom, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }

            Text(prompt)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(8)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                Button("Send to Lumina") {
                    appState.openChat(prefill: prompt)
                    onSend()
                }
                .buttonStyle(.borderedProminent)

                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = prompt
                    copied = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(LVSpacing.md)
    }
}
