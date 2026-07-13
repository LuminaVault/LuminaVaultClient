import LuminaVaultShared
import SwiftUI

struct ModelEffectivenessDetailView: View {
    let models: [ModelEffectivenessDTO]
    let ratedModelIDs: Set<String>
    let onRate: (ModelEffectivenessDTO, ModelFeedbackRating) -> Void

    var body: some View {
        List {
            Section {
                Text("Effectiveness compares reliability, fallback frequency, latency, token use, and estimated cost. It does not inspect or store prompt content.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Models") {
                ForEach(models) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent {
                            Text(model.provider).foregroundStyle(.secondary)
                        } label: {
                            Text(model.model).bold()
                        }
                        LabeledContent("Requests", value: model.requests.formatted())
                        LabeledContent(
                            "Success",
                            value: model.successRate.formatted(.percent.precision(.fractionLength(0)))
                        )
                        LabeledContent(
                            "Fallback",
                            value: model.fallbackRate.formatted(.percent.precision(.fractionLength(0)))
                        )
                        LabeledContent("Average latency", value: "\(model.averageLatencyMs) ms")
                        LabeledContent("P95 latency", value: "\(model.p95LatencyMs) ms")
                        LabeledContent(
                            "Estimated cost",
                            value: (Double(model.estimatedCostUsdMicros) / 1_000_000)
                                .formatted(.currency(code: "USD"))
                        )
                        if let satisfactionRate = model.satisfactionRate {
                            LabeledContent(
                                "Helpful",
                                value: satisfactionRate.formatted(.percent.precision(.fractionLength(0)))
                            )
                        }
                        HStack {
                            Button("Helpful", systemImage: "hand.thumbsup") {
                                onRate(model, .positive)
                            }
                            Button("Not helpful", systemImage: "hand.thumbsdown") {
                                onRate(model, .negative)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(ratedModelIDs.contains(model.id))
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .navigationTitle("Model effectiveness")
        .navigationBarTitleDisplayMode(.inline)
    }
}
