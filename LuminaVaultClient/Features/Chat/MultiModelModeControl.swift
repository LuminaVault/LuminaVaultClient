import LuminaVaultShared
import SwiftUI

/// HER-299 Stage 6 — multi-model is a per-conversation mode, not per-turn
/// status, so it lives in the chat's navigation bar rather than in a bar
/// above the composer stealing the transcript's vertical space. A switch
/// plus a five-way strategy picker is far too wide for a toolbar item, so
/// it collapses into a menu.
struct MultiModelModeControl: View {
    @Binding var isEnabled: Bool
    @Binding var strategy: ParallelStrategyDTO
    let isStreaming: Bool

    var body: some View {
        Menu {
            Toggle("Multi-Model", isOn: $isEnabled)

            if isEnabled {
                Picker("Strategy", selection: $strategy) {
                    ForEach(ParallelStrategyDTO.allCases, id: \.self) { option in
                        Text(label(for: option)).tag(option)
                    }
                }
            }
        } label: {
            Label(menuTitle, systemImage: "point.3.connected.trianglepath.dotted")
        }
        .disabled(isStreaming)
        .accessibilityHint("Turns multi-model answers on and chooses how perspectives are combined")
    }

    /// Doubles as the accessibility label, so it states the mode rather than
    /// just naming the control.
    private var menuTitle: String {
        isEnabled ? "Multi-Model on, \(label(for: strategy))" : "Multi-Model off"
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
