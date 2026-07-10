import SwiftUI

struct ParallelProgressButton: View {
    @Environment(\.lvPalette) private var palette
    let execution: ParallelChatExecution
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LVSpacing.sm) {
                Image(systemName: "rectangle.split.3x1")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Perspectives")
                        .font(.footnote.weight(.semibold))
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                if execution.status == .running {
                    ProgressView().controlSize(.small)
                }
                Image(systemName: "chevron.up")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .padding(LVSpacing.sm)
            .background(palette.surface.opacity(0.92), in: .rect(cornerRadius: LVRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(statusText)")
    }

    private var statusText: String {
        let completed = execution.perspectives.count(where: { $0.status == .completed })
        return "\(completed) of \(max(completed, execution.perspectives.count)) models · \(execution.status.rawValue)"
    }
}
