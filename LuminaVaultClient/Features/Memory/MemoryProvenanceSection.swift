import LuminaVaultShared
import SwiftUI

struct MemoryProvenanceSection: View {
    let response: MemoryProvenanceResponse?

    var body: some View {
        Section("Source") {
            if let response, !response.contributions.isEmpty {
                ForEach(response.contributions) { contribution in
                    LabeledContent {
                        Text(contribution.createdAt, format: .dateTime.year().month().day().hour().minute())
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(MemoryProvenanceText.describe(contribution), systemImage: icon(for: contribution.actor))
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                ProgressView("Loading attribution…")
            }
        }
    }

    private func icon(for actor: MemoryActorKindDTO) -> String {
        switch actor {
        case .user: "person.fill"
        case .model: "cpu"
        case .system: "gearshape.fill"
        }
    }
}
