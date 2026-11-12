// Ask how things connect: the question box, the streamed answer, the evidence
// behind it, the reasoning paths, and the connections the extractor proposed
// for review. A port of the web app's `BrainReasoningPanel.svelte`, same
// strings. A sheet that stops at medium height with the graph still usable
// behind it, so the memories an answer names can be seen lighting up.

import LuminaVaultShared
import SwiftUI

struct KnowledgeReasoningSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    let viewModel: KnowledgeReasoningViewModel
    /// The active vault's name; answers come from it alone.
    let vaultName: String?
    let memoryClient: (any MemoryClientProtocol)?

    @State private var selectedEvidence: KnowledgeEvidenceDTO?

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            List {
                Section {
                    TextField("Ask how your notes connect…", text: $viewModel.query, axis: .vertical)
                        .lineLimit(2 ... 5)
                        .submitLabel(.send)
                        .onSubmit { viewModel.reason() }
                        .accessibilityLabel("Question")
                        .accessibilityIdentifier("brain.reasoning.question")
                    Button(viewModel.loading ? "Asking…" : "Ask") { viewModel.reason() }
                        .disabled(viewModel.loading || viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("brain.reasoning.ask")
                }

                if let error = viewModel.error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                if viewModel.loading, viewModel.result == nil, viewModel.explanation == nil {
                    Section {
                        HStack(spacing: LVSpacing.sm) {
                            ProgressView()
                            Text("Tracing the connection…").foregroundStyle(palette.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if let explanation = viewModel.explanation {
                    explanationSection(explanation)
                }

                if let result = viewModel.result {
                    resultSections(result)
                }

                // The vault line stays with an answer on show: the graph spans
                // every vault, the answers do not.
                Section {
                    if !viewModel.loading, viewModel.result == nil, viewModel.explanation == nil, viewModel.error == nil {
                        Text("Ask how your notes and memories connect.")
                            .foregroundStyle(palette.textPrimary)
                    }
                    Text("Answers draw on the knowledge in \(vaultName ?? "your current vault").")
                        .font(.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .textCase(nil)
            .navigationTitle("Ask your graph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .sheet(item: $selectedEvidence) { evidence in
                KnowledgeEvidenceDetailSheet(evidence: evidence, memoryClient: memoryClient)
            }
        }
        .presentationDetents([.medium, .large])
        // No focus on open (the web panel does focus its question box): the
        // keyboard would lift the sheet to full height and cover the graph
        // and the memories the answer lights up.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    // MARK: Sections

    private func explanationSection(_ explanation: ConnectionExplanationResponse) -> some View {
        Section("Why this connects") {
            if let subject = viewModel.explanationSubject {
                Text(subject).font(.headline)
            }
            Text(explanation.explanation)
            confidence(explanation.confidence, "confidence")
            ForEach(explanation.caveats, id: \.self, content: caveat)
            ForEach(explanation.paths, content: pathRow)
        }
    }

    @ViewBuilder
    private func resultSections(_ result: ReasoningQueryResponse) -> some View {
        Section("Answer") {
            Text(result.answer.isEmpty ? " " : result.answer)
                .textSelection(.enabled)
            confidence(result.confidence, "confidence")
            ForEach(result.caveats, id: \.self, content: caveat)
        }

        if !result.evidence.isEmpty {
            Section("Evidence") {
                ForEach(result.evidence) { evidence in
                    Button { selectedEvidence = evidence } label: {
                        VStack(alignment: .leading, spacing: LVSpacing.xs) {
                            Text(evidence.quote)
                                .foregroundStyle(palette.textPrimary)
                            Text("Open memory")
                                .font(.caption)
                                .foregroundStyle(palette.primary)
                        }
                    }
                }
            }
        }

        if !result.paths.isEmpty {
            Section("Paths") {
                ForEach(result.paths, content: pathRow)
            }
        }

        if !result.suggestions.isEmpty {
            Section("Connections to review") {
                ForEach(result.suggestions, content: suggestionRow)
            }
        }
    }

    private func pathRow(_ path: KnowledgePathDTO) -> some View {
        let selected = viewModel.selectedPathID == path.id
        return Button {
            viewModel.selectPath(selected ? nil : path.id)
        } label: {
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                Text(Self.pathLabel(path))
                    .foregroundStyle(palette.textPrimary)
                Text("\(Self.pct(path.confidence)) path confidence")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .listRowBackground(selected ? palette.accent.opacity(0.14) : nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func suggestionRow(_ edge: KnowledgeEdgeDTO) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Button("\(Self.predicate(edge)) · \(Self.pct(edge.confidence))") {
                viewModel.explainNodes(from: edge.from, to: edge.to)
            }
            .buttonStyle(.borderless)
            if let rationale = edge.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            if let counter = edge.counterEvidence, !counter.isEmpty {
                caveat(counter).font(.caption)
            }
            HStack(spacing: LVSpacing.sm) {
                Button("Confirm") { viewModel.review(edge, action: .confirm) }
                    .buttonStyle(.bordered)
                Button("Dismiss") { viewModel.review(edge, action: .dismiss) }
                    .buttonStyle(.borderless)
            }
            .disabled(viewModel.reviewing != nil)
        }
        .padding(.vertical, LVSpacing.xs)
    }

    private func confidence(_ value: Double, _ noun: String) -> some View {
        Text("\(Self.pct(value)) \(noun)")
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
    }

    private func caveat(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(palette.accent)
    }

    // MARK: Formatting (the web panel's helpers)

    static func pct(_ n: Double) -> String {
        "\(Int((n * 100).rounded()))%"
    }

    static func pathLabel(_ path: KnowledgePathDTO) -> String {
        let label = path.nodes.map(\.label).joined(separator: " → ")
        return label.isEmpty ? "Path" : label
    }

    static func predicate(_ edge: KnowledgeEdgeDTO) -> String {
        edge.predicate.rawValue.replacingOccurrences(of: "_", with: " ")
    }
}
