import LuminaVaultShared
import SwiftUI

struct MultiModelModeControl: View {
    @Environment(\.lvPalette) private var palette
    @Binding var isEnabled: Bool
    @Binding var strategy: ParallelStrategyDTO
    let isStreaming: Bool

    var body: some View {
        HStack(spacing: LVSpacing.sm) {
            Toggle("Multi-Model", isOn: $isEnabled)
                .toggleStyle(.switch)
                .tint(palette.accent)
                .disabled(isStreaming)

            Spacer(minLength: 0)

            if isEnabled {
                Menu("Strategy: \(label(for: strategy))", systemImage: "point.3.connected.trianglepath.dotted") {
                    ForEach(ParallelStrategyDTO.allCases, id: \.self) { option in
                        Button(label(for: option)) { strategy = option }
                    }
                }
                .disabled(isStreaming)
                .accessibilityHint("Chooses how model perspectives are combined")
            }
        }
        .font(.footnote)
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, LVSpacing.base)
        .padding(.vertical, LVSpacing.sm)
        .background(palette.surface.opacity(0.92), in: .rect(cornerRadius: LVRadius.md))
    }

    private func label(for strategy: ParallelStrategyDTO) -> String {
        switch strategy {
        case .auto: "Auto"
        case .bestOfN: "Best of N"
        case .debate: "Debate"
        case .consensus: "Consensus"
        case .specialist: "Specialists"
        }
    }
}
