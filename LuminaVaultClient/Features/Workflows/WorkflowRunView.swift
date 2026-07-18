import LuminaVaultShared
import SwiftUI

@Observable @MainActor
final class WorkflowRunViewModel {
    private(set) var run: WorkflowRunDTO?
    private(set) var events: [WorkflowRunEventDTO] = []
    private(set) var isLive = false
    private(set) var canControl = false
    private(set) var errorMessage: String?
    private let runID: UUID
    private let client: any WorkflowsClientProtocol

    init(runID: UUID, client: any WorkflowsClientProtocol) {
        self.runID = runID
        self.client = client
    }

    func monitor() async {
        await loadAccess()
        await refresh()
        guard let run, !run.status.isStudioTerminal else { return }
        isLive = true
        defer { isLive = false }
        do {
            for try await event in client.events(runID: runID) {
                if !events.contains(where: { $0.id == event.id }) {
                    events.append(event)
                }
                await refresh()
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        do {
            run = try await client.runDetail(runID: runID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() async {
        do {
            try await client.cancel(runID: runID)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resume() async {
        do {
            run = try await client.resume(runID: runID)
            await monitor()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retry() async -> UUID? {
        do { return try await client.retry(runID: runID).id } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func loadAccess() async {
        do {
            canControl = try await client.limits().canAuthor
        } catch {
            canControl = false
        }
    }
}

struct WorkflowRunView: View {
    @State private var viewModel: WorkflowRunViewModel
    @State private var retryRunID: UUID?
    private let client: any WorkflowsClientProtocol

    init(runID: UUID, client: any WorkflowsClientProtocol) {
        self.client = client
        _viewModel = State(initialValue: WorkflowRunViewModel(runID: runID, client: client))
    }

    var body: some View {
        List {
            if let run = viewModel.run {
                Section {
                    HStack {
                        Label(run.status.rawValue.capitalized, systemImage: icon(run.status))
                            .font(.headline)
                        Spacer()
                        if viewModel.isLive {
                            Label("Live", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    LabeledContent("Managed spend", value: money(run.managedSpendUsdMicros))
                    LabeledContent("Run ceiling", value: money(run.managedSpendLimitUsdMicros))
                    if let reason = run.pauseReason {
                        Label(reason.rawValue, systemImage: "pause.circle")
                            .foregroundStyle(.orange)
                    }
                    if let error = run.error {
                        Text(error).font(.subheadline).foregroundStyle(.red)
                    }
                    if viewModel.canControl {
                        if run.status == .paused {
                            Button("Resume", systemImage: "play.fill") { Task { await viewModel.resume() } }
                        } else if run.status.isStudioTerminal {
                            Button("Retry", systemImage: "arrow.clockwise") {
                                Task { retryRunID = await viewModel.retry() }
                            }
                        } else {
                            Button("Cancel run", systemImage: "stop.circle", role: .destructive) {
                                Task { await viewModel.cancel() }
                            }
                        }
                    }
                }

                Section("Steps") {
                    ForEach(run.nodeRuns) { node in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(node.nodeName).font(.headline)
                                Spacer()
                                Text(node.status.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let provider = node.provider, let model = node.model {
                                Label("\(provider) · \(model)", systemImage: "cpu")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let preview = node.outputPreview {
                                Text(preview).font(.subheadline).textSelection(.enabled)
                            }
                            if node.tokensIn != nil || node.tokensOut != nil {
                                Text("\(node.tokensIn ?? 0) in · \(node.tokensOut ?? 0) out · \(money(node.managedCostUsdMicros))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !viewModel.events.isEmpty {
                    Section("Live events") {
                        ForEach(viewModel.events.reversed()) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.kind.rawValue).font(.subheadline.weight(.medium))
                                Text(event.message ?? event.createdAt.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(viewModel.run?.workflowName ?? "Workflow run")
        .task { await viewModel.monitor() }
        .refreshable { await viewModel.refresh() }
        .navigationDestination(item: $retryRunID) { runID in
            WorkflowRunView(runID: runID, client: client)
        }
        .alert("Studio update", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissError()
                }
            }
        )) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func icon(_ status: WorkflowRunStatus) -> String {
        switch status {
        case .succeeded: "checkmark.circle.fill"
        case .failed, .timedOut: "exclamationmark.triangle.fill"
        case .waitingForApproval: "person.crop.circle.badge.questionmark"
        case .paused: "pause.circle.fill"
        case .cancelled: "xmark.circle"
        case .queued, .running: "clock.arrow.circlepath"
        }
    }

    private func money(_ micros: Int64?) -> String {
        (Double(micros ?? 0) / 1_000_000).formatted(.currency(code: "USD"))
    }
}

private extension WorkflowRunStatus {
    var isStudioTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .timedOut, .paused: true
        case .queued, .running, .waitingForApproval: false
        }
    }
}
