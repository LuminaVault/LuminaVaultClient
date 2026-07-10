import LuminaVaultShared
import SwiftUI

@Observable @MainActor
final class WorkflowDetailViewModel {
    private(set) var runs: [WorkflowRunDTO] = []
    private(set) var loading = true
    private let workflowID: UUID
    private let client: any WorkflowsClientProtocol
    init(workflowID: UUID, client: any WorkflowsClientProtocol) {
        self.workflowID = workflowID; self.client = client
    }

    func load() async {
        loading = true; defer { loading = false }; runs = (try? await client.runs(workflowID: workflowID).runs) ?? []
    }

    func run() async {
        _ = try? await client.run(workflowID: workflowID, input: [:], conversationID: nil); await load()
    }
}

struct WorkflowDetailView: View {
    @State private var viewModel: WorkflowDetailViewModel
    init(workflowID: UUID, client: any WorkflowsClientProtocol) {
        _viewModel = State(initialValue: WorkflowDetailViewModel(workflowID: workflowID, client: client))
    }

    var body: some View {
        List {
            Section { Button("Run workflow", systemImage: "play.fill") { Task { await viewModel.run() } }.buttonStyle(.borderedProminent) }
            Section("Execution history") {
                ForEach(viewModel.runs) { run in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(run.status.rawValue.capitalized, systemImage: run.status == .succeeded ? "checkmark.circle" : "clock")
                        Text(run.createdAt, format: .dateTime.month().day().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                        if let error = run.error {
                            Text(error).font(.subheadline).foregroundStyle(.red)
                        }
                    }.padding(.vertical, 4)
                }
            }
        }.navigationTitle("Workflow").overlay {
            if viewModel.loading {
                ProgressView()
            }
        }.task { await viewModel.load() }.refreshable { await viewModel.load() }
    }
}
