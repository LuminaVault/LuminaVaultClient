import LuminaVaultShared
import SwiftUI

@Observable @MainActor
final class WorkflowListViewModel {
    enum State { case loading, loaded, failed }
    private(set) var state = State.loading
    private(set) var workflows: [WorkflowSummaryDTO] = []
    private(set) var runs: [WorkflowRunDTO] = []
    private(set) var approvals: [WorkflowApprovalDTO] = []
    private(set) var templates: [WorkflowTemplateDTO] = []
    private(set) var limits: WorkflowLimitsDTO?
    private(set) var workingIDs: Set<UUID> = []
    private(set) var errorMessage: String?
    private let client: any WorkflowsClientProtocol

    init(client: any WorkflowsClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        errorMessage = nil
        do {
            async let templateResponse = client.templates()
            async let limitResponse = client.limits()
            let browse = try await (templateResponse, limitResponse)
            templates = browse.0.templates
            limits = browse.1

            if browse.1.tier == .trial {
                workflows = []
                runs = []
                approvals = []
                state = .loaded
                return
            }

            async let workflowResponse = client.list()
            async let runResponse = client.runs(workflowID: nil)
            let history = try await (workflowResponse, runResponse)
            workflows = history.0.workflows
            runs = history.1.runs
            if browse.1.canAuthor {
                let response = try await client.approvals()
                approvals = response.approvals
            } else {
                approvals = []
            }
            state = .loaded
        } catch {
            errorMessage = error.localizedDescription
            state = .failed
        }
    }

    func run(_ workflow: WorkflowSummaryDTO) async -> UUID? {
        guard workingIDs.insert(workflow.id).inserted else { return nil }
        defer { workingIDs.remove(workflow.id) }
        do {
            let run = try await client.run(workflowID: workflow.id, input: [:], conversationID: nil)
            await load()
            return run.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func run(template: WorkflowTemplateDTO) async -> UUID? {
        do {
            let run = try await client.runTemplate(templateID: template.id)
            await load()
            return run.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func decide(_ approval: WorkflowApprovalDTO, approved: Bool, memoryIDs: [UUID] = []) async {
        guard workingIDs.insert(approval.id).inserted else { return }
        defer { workingIDs.remove(approval.id) }
        do {
            try await client.decide(approvalID: approval.id, approved: approved, memoryIDs: memoryIDs)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct WorkflowListView: View {
    @Environment(NotificationRouter.self) private var notificationRouter
    @State private var viewModel: WorkflowListViewModel
    @State private var selectedApproval: WorkflowApprovalDTO?
    @State private var runPath: [UUID] = []
    private let client: any WorkflowsClientProtocol
    private let memoryClient: any MemoryClientProtocol

    init(client: any WorkflowsClientProtocol, memoryClient: any MemoryClientProtocol) {
        self.client = client
        self.memoryClient = memoryClient
        _viewModel = State(initialValue: WorkflowListViewModel(client: client))
    }

    var body: some View {
        NavigationStack(path: $runPath) {
            List {
                if let limits = viewModel.limits {
                    Section {
                        StudioAllowanceCard(limits: limits)
                    }
                    .listRowBackground(Color.clear)

                    if !limits.canAuthor {
                        Section {
                            Label(
                                limits.tier == .trial
                                    ? "Upgrade to Pro or Ultimate to build and run workflows."
                                    : "Your workflow history is read-only on this plan.",
                                systemImage: "lock"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                if !viewModel.approvals.isEmpty {
                    Section("Waiting for you") {
                        ForEach(viewModel.approvals) { approval in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(approval.title).font(.headline)
                                Text(approval.workflowName).foregroundStyle(.secondary)
                                if let message = approval.message {
                                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Button("Review", systemImage: "paperclip") {
                                        selectedApproval = approval
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Button("Reject", systemImage: "xmark") {
                                        Task { await viewModel.decide(approval, approved: false) }
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !viewModel.templates.isEmpty {
                    Section("Start from a template") {
                        ForEach(viewModel.templates) { template in
                            Button {
                                Task {
                                    if let runID = await viewModel.run(template: template) {
                                        runPath.append(runID)
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(template.name).font(.headline)
                                        Spacer()
                                        Image(systemName: "play.circle.fill")
                                    }
                                    Text(template.descriptionText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(template.category.uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                                .padding(.vertical, 4)
                            }
                            .disabled(viewModel.limits?.canAuthor == false)
                        }
                    }
                }

                Section("Your workflows") {
                    ForEach(viewModel.workflows) { workflow in
                        NavigationLink {
                            WorkflowDetailView(
                                workflowID: workflow.id,
                                client: client,
                                canRun: viewModel.limits?.canAuthor == true
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(workflow.name).font(.headline)
                                    Spacer()
                                    Text(workflow.trigger.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let status = workflow.lastRunStatus {
                                    Label(status.rawValue, systemImage: icon(status))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions {
                            if viewModel.limits?.canAuthor == true {
                                Button("Run", systemImage: "play.fill") {
                                    Task {
                                        if let runID = await viewModel.run(workflow) {
                                            runPath.append(runID)
                                        }
                                    }
                                }
                                .tint(.accentColor)
                            }
                        }
                    }
                }

                if !viewModel.runs.isEmpty {
                    Section("Recent runs") {
                        ForEach(viewModel.runs.prefix(12)) { run in
                            NavigationLink(value: run.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(run.workflowName).font(.headline)
                                    Label(run.status.rawValue, systemImage: icon(run.status))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cerberus Studio")
            .navigationDestination(for: UUID.self) { runID in
                WorkflowRunView(runID: runID, client: client)
            }
            .overlay {
                if viewModel.state == .loading {
                    ProgressView()
                }
            }
            .overlay {
                if viewModel.state == .loaded, viewModel.workflows.isEmpty,
                   viewModel.templates.isEmpty
                {
                    ContentUnavailableView(
                        "Studio is ready",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Build workflows on the web, then trigger and monitor them here.")
                    )
                }
            }
            .task { await viewModel.load() }
            .task(id: notificationRouter.pendingDeepLink) {
                if case let .workflow(runID) = notificationRouter.pendingDeepLink {
                    runPath.append(runID)
                    _ = notificationRouter.consume()
                }
            }
            .refreshable { await viewModel.load() }
            .sheet(item: $selectedApproval) { approval in
                WorkflowApprovalSheet(
                    approval: approval,
                    memoryClient: memoryClient,
                    onApprove: { memoryIDs in
                        await viewModel.decide(approval, approved: true, memoryIDs: memoryIDs)
                    }
                )
            }
        }
    }

    private func icon(_ status: WorkflowRunStatus) -> String {
        switch status {
        case .succeeded: "checkmark.circle"
        case .failed, .timedOut: "exclamationmark.triangle"
        case .waitingForApproval: "person.crop.circle.badge.questionmark"
        case .running, .queued: "clock"
        case .paused: "pause.circle"
        case .cancelled: "xmark.circle"
        }
    }
}

private struct StudioAllowanceCard: View {
    let limits: WorkflowLimitsDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(limits.tier.rawValue.capitalized, systemImage: "shield.checkered")
                    .font(.headline)
                Spacer()
                Text("\(limits.activeRuns)/\(limits.activeRunLimit) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(limits.dailySpentUsdMicros), total: Double(max(1, limits.dailyLimitUsdMicros)))
            HStack {
                Text("Today \(money(limits.dailySpentUsdMicros)) / \(money(limits.dailyLimitUsdMicros))")
                Spacer()
                Text("\(limits.minimumScheduleMinutes)m minimum schedule")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !limits.managedInferenceAvailable {
                Label("Managed inference is temporarily unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    private func money(_ micros: Int64) -> String {
        (Double(micros) / 1_000_000).formatted(.currency(code: "USD"))
    }
}

@Observable @MainActor
private final class WorkflowApprovalViewModel {
    private(set) var memories: [MemoryDTO] = []
    var selection: Set<UUID> = []
    private let client: any MemoryClientProtocol

    init(client: any MemoryClientProtocol) {
        self.client = client
    }

    func load() async {
        memories = (try? await client.list(limit: 50, offset: 0).memories) ?? []
    }

    func toggle(_ memoryID: UUID) {
        if !selection.insert(memoryID).inserted {
            selection.remove(memoryID)
        }
    }
}

private struct WorkflowApprovalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WorkflowApprovalViewModel
    let approval: WorkflowApprovalDTO
    let onApprove: @MainActor ([UUID]) async -> Void

    init(
        approval: WorkflowApprovalDTO,
        memoryClient: any MemoryClientProtocol,
        onApprove: @escaping @MainActor ([UUID]) async -> Void
    ) {
        self.approval = approval
        self.onApprove = onApprove
        _viewModel = State(initialValue: WorkflowApprovalViewModel(client: memoryClient))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(approval.message ?? "Review this gate before the workflow continues.")
                }
                Section("Attach memories to this gate") {
                    ForEach(viewModel.memories) { memory in
                        Button {
                            viewModel.toggle(memory.id)
                        } label: {
                            HStack {
                                Text(memory.content).lineLimit(2)
                                Spacer()
                                if viewModel.selection.contains(memory.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(approval.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Approve") {
                        Task {
                            await onApprove(Array(viewModel.selection))
                            dismiss()
                        }
                    }
                }
            }
            .task { await viewModel.load() }
        }
    }
}
