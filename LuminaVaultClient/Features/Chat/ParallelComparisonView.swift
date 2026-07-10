import SwiftUI

struct ParallelComparisonPresentation: Identifiable {
    let id: UUID
}

struct ParallelComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LVSpacing.base) {
                    if let execution = viewModel.parallelExecution {
                        Text(execution.strategy.rawValue)
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(palette.accent)

                        ForEach(execution.perspectives) { output in
                            ParallelOutputCard(output: output)
                        }
                    } else {
                        ContentUnavailableView(
                            "No perspectives",
                            systemImage: "rectangle.split.3x1",
                            description: Text("Run a multi-model turn to compare answers.")
                        )
                    }
                }
                .padding(LVSpacing.lg)
            }
            .navigationTitle("Model Perspectives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

private struct ParallelOutputCard: View {
    @Environment(\.lvPalette) private var palette
    let output: ParallelChatOutput

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(output.role).font(.headline)
                    if let route = output.route {
                        Text("\(route.provider.rawValue) · \(route.model)")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Label(output.status.rawValue, systemImage: statusSymbol)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(statusColor)
                    .accessibilityLabel(output.status.rawValue)
            }

            if output.content.isEmpty, output.status == .running {
                ProgressView("Waiting for first token…")
                    .font(.caption)
            } else {
                Text(output.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(LVSpacing.base)
        .background(palette.surface, in: .rect(cornerRadius: LVRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: LVRadius.lg)
                .stroke(palette.accent.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var statusSymbol: String {
        switch output.status {
        case .running: "ellipsis.circle"
        case .completed: "checkmark.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .failed, .cancelled: "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch output.status {
        case .running: palette.accent
        case .completed: .green
        case .degraded: .orange
        case .failed, .cancelled: .red
        }
    }
}
