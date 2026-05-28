// HER-287 — Screen 2: Goal question (single-select).
import SwiftUI

struct GoalQuestionView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(\.lvPalette) private var palette

    var body: some View {
        FunnelScreenChrome(
            headline: "What should Lumina help you with first?",
            subhead: "One pick. You can change later.",
            primaryCTA: "Continue",
            primaryEnabled: state.selectedGoal != nil,
            onPrimary: { state.advance() }
        ) {
            VStack(spacing: 10) {
                ForEach(FunnelGoal.allCases) { goal in
                    Button {
                        state.selectGoal(goal)
                    } label: {
                        row(for: goal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for goal: FunnelGoal) -> some View {
        let selected = state.selectedGoal == goal
        HStack(spacing: 14) {
            Text(goal.emoji)
                .font(.system(size: 22))
            Text(goal.label)
                .font(.system(size: 16, weight: selected ? .semibold : .regular))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if selected {
                LVIconView(.checkmarkCircleFill, tint: palette.glowPrimary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? palette.glowPrimary.opacity(0.15) : palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    selected ? palette.glowPrimary : Color.gray.opacity(0.2),
                    lineWidth: selected ? 1.5 : 1
                )
        )
    }
}
