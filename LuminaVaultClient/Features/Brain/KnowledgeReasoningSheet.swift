import Foundation
import LuminaVaultShared
import SwiftUI

struct KnowledgeReasoningSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette
    @State var viewModel: KnowledgeReasoningViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Ask your graph") {
                    TextField("What changed my view on…?", text: $viewModel.query, axis: .vertical)
                        .lineLimit(2 ... 5)
                    Button("Trace evidence", systemImage: "point.3.connected.trianglepath.dotted", action: runReasoning)
                        .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isReasoning)
                }

                if viewModel.isReasoning {
                    Section { ProgressView("Following connections…") }
                }

                if let result = viewModel.result {
                    Section("Grounded answer") {
                        Text(result.answer)
                        LabeledContent("Confidence", value: result.confidence, format: .percent.precision(.fractionLength(0)))
                        ForEach(result.caveats, id: \.self) { caveat in
                            Label(caveat, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(palette.accent)
                        }
                    }
                    if !result.evidence.isEmpty {
                        Section("Evidence") {
                            ForEach(result.evidence) { evidence in
                                Text(evidence.quote)
                                    .font(.callout)
                                    .accessibilityLabel("Evidence: \(evidence.quote)")
                            }
                        }
                    }
                    if !result.suggestions.isEmpty {
                        Section("Connections to review") {
                            ForEach(result.suggestions) { edge in
                                VStack(alignment: .leading, spacing: 10) {
                                    Button(edge.predicate.accessibleLabel, systemImage: "questionmark.circle") {
                                        Task { await viewModel.explain(edge) }
                                    }
                                    Text(edge.rationale ?? "Machine-inferred connection")
                                        .font(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                    HStack {
                                        Button("Confirm", systemImage: "checkmark.circle") {
                                            Task { await viewModel.review(edge, action: .confirm) }
                                        }
                                        Button("Dismiss", systemImage: "xmark.circle") {
                                            Task { await viewModel.review(edge, action: .dismiss) }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }

                if let explanation = viewModel.explanation {
                    Section("Why this connects") {
                        Text(explanation.explanation)
                        LabeledContent("Path confidence", value: explanation.confidence, format: .percent.precision(.fractionLength(0)))
                        ForEach(explanation.caveats, id: \.self) { caveat in
                            Label(caveat, systemImage: "sparkles")
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Reasoning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .task { await viewModel.load() }
        }
    }

    private func runReasoning() {
        Task { await viewModel.reason() }
    }
}

private extension KnowledgeEdgePredicateDTO {
    var accessibleLabel: String {
        switch self {
        case .mentions: "Explain mention"
        case .about: "Explain topic connection"
        case .supports: "Explain supporting connection"
        case .contradicts: "Explain contradiction"
        case .causes: "Explain causal connection"
        case .precedes: "Explain timeline connection"
        case .relatedTo: "Explain related connection"
        case .derivedFrom: "Explain source connection"
        }
    }
}
