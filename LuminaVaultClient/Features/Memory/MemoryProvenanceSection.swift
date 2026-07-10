import LuminaVaultShared
import SwiftUI

struct MemoryProvenanceSection: View {
    let response: MemoryProvenanceResponse?

    var body: some View {
        Section("Contributors") {
            if let response, !response.contributions.isEmpty {
                ForEach(response.contributions) { contribution in
                    LabeledContent {
                        Text(contribution.createdAt, format: .dateTime.year().month().day().hour().minute())
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(title(for: contribution), systemImage: icon(for: contribution.actor))
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                ProgressView("Loading attribution…")
            }
        }
    }

    private func title(for contribution: MemoryContributionDTO) -> String {
        if let model = contribution.model {
            return "\(model.model) · \(contribution.operation.rawValue.capitalized)"
        }
        return "\(contribution.actor.rawValue.capitalized) · \(contribution.source.rawValue.replacing("_", with: " ").capitalized)"
    }

    private func icon(for actor: MemoryActorKindDTO) -> String {
        switch actor {
        case .user: "person.fill"
        case .model: "cpu"
        case .system: "gearshape.fill"
        }
    }
}
