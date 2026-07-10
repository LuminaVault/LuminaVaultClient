import LuminaVaultShared
import SwiftUI

struct ChatWorkflowPicker: View {
    @Environment(\.dismiss) private var dismiss
    let client: any WorkflowsClientProtocol
    let conversationID: UUID?
    @State private var workflows: [WorkflowSummaryDTO] = []
    @State private var runningID: UUID?
    @State private var failed = false

    var body: some View {
        List(workflows) { workflow in
            Button {
                Task { await run(workflow) }
            } label: {
                HStack {
                    Label(workflow.name, systemImage: "point.3.connected.trianglepath.dotted")
                    Spacer()
                    if runningID == workflow.id {
                        ProgressView()
                    }
                }
            }
            .disabled(runningID != nil)
        }
        .navigationTitle("Run a workflow")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .overlay {
            if workflows.isEmpty, !failed {
                ProgressView()
            }
        }
        .overlay {
            if failed {
                ContentUnavailableView("Couldn't load workflows", systemImage: "exclamationmark.triangle")
            }
        }
        .task {
            do { workflows = try await client.list().workflows.filter { $0.enabled && $0.publishedVersion != nil } }
            catch { failed = true }
        }
    }

    private func run(_ workflow: WorkflowSummaryDTO) async {
        runningID = workflow.id
        do { _ = try await client.run(workflowID: workflow.id, input: [:], conversationID: conversationID); dismiss() }
        catch { failed = true; runningID = nil }
    }
}
