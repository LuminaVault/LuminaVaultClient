import LuminaVaultShared
import SwiftUI

@Observable @MainActor
final class WorkflowListViewModel {
    enum State { case loading, loaded, failed }
    private(set) var state = State.loading
    private(set) var workflows: [WorkflowSummaryDTO] = []
    private(set) var approvals: [WorkflowApprovalDTO] = []
    private(set) var workingIDs: Set<UUID> = []
    private let client: any WorkflowsClientProtocol
    init(client: any WorkflowsClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            async let workflowResponse = client.list()
            async let approvalResponse = client.approvals()
            let (loadedWorkflows, loadedApprovals) = try await (workflowResponse, approvalResponse)
            workflows = loadedWorkflows.workflows
            approvals = loadedApprovals.approvals
            state = .loaded
        } catch { state = .failed }
    }

    func run(_ workflow: WorkflowSummaryDTO) async {
        guard workingIDs.insert(workflow.id).inserted else { return }
        defer { workingIDs.remove(workflow.id) }
        _ = try? await client.run(workflowID: workflow.id, input: [:], conversationID: nil)
        await load()
    }

    func decide(_ approval: WorkflowApprovalDTO, approved: Bool) async {
        guard workingIDs.insert(approval.id).inserted else { return }
        defer { workingIDs.remove(approval.id) }
        try? await client.decide(approvalID: approval.id, approved: approved)
        await load()
    }
}

struct WorkflowListView: View {
    @State private var viewModel: WorkflowListViewModel
    private let client: any WorkflowsClientProtocol
    init(client: any WorkflowsClientProtocol) {
        self.client = client; _viewModel = State(initialValue: WorkflowListViewModel(client: client))
    }

    var body: some View {
        List {
            if !viewModel.approvals.isEmpty {
                Section("Needs approval") {
                    ForEach(viewModel.approvals) { approval in
                        VStack(alignment: .leading) {
                            Text(approval.title).font(.headline)
                            Text(approval.workflowName).foregroundStyle(.secondary)
                            HStack {
                                Button("Approve", systemImage: "checkmark") { Task { await viewModel.decide(approval, approved: true) } }.buttonStyle(.borderedProminent)
                                Button("Reject", systemImage: "xmark") { Task { await viewModel.decide(approval, approved: false) } }.buttonStyle(.bordered)
                            }.controlSize(.small)
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section("Your workflows") {
                ForEach(viewModel.workflows) { workflow in
                    NavigationLink(value: workflow.id) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(workflow.name).font(.headline); Spacer(); Text(workflow.trigger.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
                            if let status = workflow.lastRunStatus {
                                Label(status.rawValue, systemImage: icon(status)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }.swipeActions { Button("Run", systemImage: "play.fill") { Task { await viewModel.run(workflow) } }.tint(.accentColor) }
                }
            }
        }
        .navigationTitle("Workflows")
        .navigationDestination(for: UUID.self) { id in WorkflowDetailView(workflowID: id, client: client) }
        .overlay {
            if viewModel.state == .loading {
                ProgressView()
            }
        }
        .overlay {
            if viewModel.state == .loaded, viewModel.workflows.isEmpty {
                ContentUnavailableView("No workflows", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Build your first workflow on the web, then run it here."))
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func icon(_ status: WorkflowRunStatus) -> String {
        switch status { case .succeeded: "checkmark.circle"; case .failed, .timedOut: "exclamationmark.triangle"; case .waitingForApproval: "person.crop.circle.badge.questionmark"; case .running, .queued: "clock"; case .cancelled: "xmark.circle" }
    }
}
