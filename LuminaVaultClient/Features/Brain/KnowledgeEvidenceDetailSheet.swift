import LuminaVaultShared
import SwiftUI

struct KnowledgeEvidenceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    let evidence: KnowledgeEvidenceDTO
    let memoryClient: (any MemoryClientProtocol)?

    @State private var memory: MemoryDTO?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Cited passage") {
                    Text(evidence.quote)
                        .textSelection(.enabled)
                }

                Section("Source memory") {
                    if isLoading {
                        ProgressView("Loading source…")
                    } else if let memory {
                        Text(memory.content)
                            .textSelection(.enabled)
                        if !memory.tags.isEmpty {
                            Text(memory.tags.map { "#\($0)" }.joined(separator: "  "))
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        if let createdAt = memory.createdAt {
                            LabeledContent("Created", value: createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    } else if let errorMessage {
                        ContentUnavailableView(
                            "Source unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    } else {
                        ContentUnavailableView(
                            "Memory access unavailable",
                            systemImage: "lock",
                            description: Text("This client cannot load the full source memory.")
                        )
                    }
                }
            }
            .navigationTitle("Evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .task(id: evidence.memoryID) { await loadMemory() }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadMemory() async {
        guard let memoryClient else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            memory = try await memoryClient.get(id: evidence.memoryID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
