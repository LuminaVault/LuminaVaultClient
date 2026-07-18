import LuminaVaultShared
import SwiftUI

@Observable @MainActor
final class WorkflowDetailViewModel {
    private(set) var runs: [WorkflowRunDTO] = []
    private(set) var loading = true
    private(set) var errorMessage: String?
    private let workflowID: UUID
    private let client: any WorkflowsClientProtocol

    init(workflowID: UUID, client: any WorkflowsClientProtocol) {
        self.workflowID = workflowID
        self.client = client
    }

    func load() async {
        loading = true
        defer { loading = false }
        do { runs = try await client.runs(workflowID: workflowID).runs } catch { errorMessage = error.localizedDescription }
    }

    func run() async -> UUID? {
        do {
            let run = try await client.run(workflowID: workflowID, input: [:], conversationID: nil)
            await load()
            return run.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

struct WorkflowDetailView: View {
    @State private var viewModel: WorkflowDetailViewModel
    @State private var selectedRunID: UUID?
    private let client: any WorkflowsClientProtocol
    private let canRun: Bool

    init(workflowID: UUID, client: any WorkflowsClientProtocol, canRun: Bool = true) {
        self.client = client
        self.canRun = canRun
        _viewModel = State(initialValue: WorkflowDetailViewModel(workflowID: workflowID, client: client))
    }

    var body: some View {
        List {
            if canRun {
                Section {
                    Button("Run workflow", systemImage: "play.fill") {
                        Task { selectedRunID = await viewModel.run() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Section("Execution history") {
                ForEach(viewModel.runs) { run in
                    NavigationLink {
                        WorkflowRunView(runID: run.id, client: client)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(run.status.rawValue.capitalized, systemImage: run.status == .succeeded ? "checkmark.circle" : "clock")
                            Text(run.createdAt, format: .dateTime.month().day().hour().minute())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Workflow")
        .overlay {
            if viewModel.loading {
                ProgressView()
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .navigationDestination(item: $selectedRunID) { runID in
            WorkflowRunView(runID: runID, client: client)
        }
    }
}
