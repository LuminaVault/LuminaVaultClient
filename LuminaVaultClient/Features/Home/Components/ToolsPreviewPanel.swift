import SwiftUI

struct ToolsPreviewPanel: View {
    @Environment(\.lvPalette) private var palette

    let tools: [String]
    let count: Int
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            HStack {
                Text("TOOLS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(palette.glowPrimary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }

            if isLoading {
                HStack {
                    Capsule().fill(Color.white.opacity(0.08)).frame(width: 56, height: 24)
                    Capsule().fill(Color.white.opacity(0.08)).frame(width: 72, height: 24)
                }
            } else if tools.isEmpty {
                Text("No extra tools installed yet.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            } else {
                FlexibleToolChips(tools: tools)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct FlexibleToolChips: View {
    @Environment(\.lvPalette) private var palette
    let tools: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            // Positional identity — see `SkillsPreviewPanel`. Tool names are
            // server strings and are not guaranteed unique.
            ForEach(Array(tools.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(palette.glowPrimary.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(palette.glowPrimary.opacity(0.3), lineWidth: 1))
                    .foregroundStyle(palette.glowPrimary)
            }
        }
    }
}
