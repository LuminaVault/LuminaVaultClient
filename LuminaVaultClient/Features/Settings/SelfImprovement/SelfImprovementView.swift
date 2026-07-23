import SwiftUI

struct SelfImprovementView: View {
    @Environment(\.lvPalette) private var palette
    @State var viewModel: SelfImprovementViewModel
    @State private var approvalCandidate: LVImprovementChange?
    @AppStorage("lv.chat.hapticsEnabled") private var hapticsEnabled = true
    @State private var pinHapticTrigger = 0
    @State private var approveHapticTrigger = 0
    @State private var rejectHapticTrigger = 0

    var body: some View {
        List {
            if let message = viewModel.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }
            if let message = viewModel.status?.message {
                Section { Text(message).foregroundStyle(palette.textSecondary) }
            }

            Section {
                Toggle("Self-improvement", isOn: $viewModel.settings.enabled)
                Toggle("Weekly curator", isOn: $viewModel.settings.curatorEnabled)
                    .disabled(!viewModel.settings.enabled)
                Toggle("Consolidate overlapping skills", isOn: $viewModel.settings.consolidate)
                    .disabled(!viewModel.settings.curatorEnabled)
                Picker("Review model", selection: $viewModel.settings.modelMode) {
                    Text("Economy").tag(LVImprovementModelMode.economy)
                    Text("Main model").tag(LVImprovementModelMode.main)
                }
            } header: {
                Text("Curator")
            } footer: {
                Text("Runs weekly after two idle hours. Built-in skills are never pruned; five guarded backups are retained.")
            }
            .disabled(!viewModel.canManage)

            Section {
                Toggle("Weekly SOUL review", isOn: $viewModel.settings.soulReviewEnabled)
                    .disabled(!viewModel.settings.enabled)
                Toggle("Review complex sessions", isOn: $viewModel.settings.reviewComplexSessions)
                    .disabled(!viewModel.settings.soulReviewEnabled)
                Stepper(
                    "Review the last \(viewModel.settings.soulReviewWindowDays) days",
                    value: $viewModel.settings.soulReviewWindowDays,
                    in: 7 ... 14
                )
                Button("Review SOUL.md now") { Task { await viewModel.reviewSoul() } }
                    .disabled(viewModel.isWorking || !viewModel.settings.enabled || !viewModel.settings.soulReviewEnabled)
            } header: {
                Text("SOUL Reviewer")
            } footer: {
                Text("SOUL.md is never changed automatically. Every conservative patch waits for your approval.")
            }
            .disabled(!viewModel.canManage)

            Section("Run now") {
                Button("Preview curator changes") { Task { await viewModel.runCurator(dryRun: true) } }
                Button("Run curator with backups") { Task { await viewModel.runCurator(dryRun: false) } }
                    .disabled(!viewModel.settings.enabled || !viewModel.settings.curatorEnabled)
            }
            .disabled(!viewModel.canManage)

            if !viewModel.pendingChanges.isEmpty {
                Section("SOUL proposals") {
                    ForEach(viewModel.pendingChanges) { change in
                        VStack(alignment: .leading, spacing: LVSpacing.sm) {
                            Text(change.title).font(LVTypography.body.font.weight(.semibold))
                            Text(change.summary).font(LVTypography.footnote.font)
                                .foregroundStyle(palette.textSecondary)
                            if let patch = change.patch {
                                Text(patch)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(12)
                            }
                            HStack {
                                Button("Reject", role: .destructive) {
                                    if hapticsEnabled { rejectHapticTrigger += 1 }
                                    Task { await viewModel.decide(change, approve: false) }
                                }
                                .disabled(!viewModel.canManage)
                                Spacer()
                                Button("Approve") { approvalCandidate = change }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!viewModel.canManage)
                            }
                        }
                        .padding(.vertical, LVSpacing.xs)
                    }
                }
            }

            Section {
                ForEach(viewModel.resources) { resource in
                    Toggle(isOn: Binding(
                        get: { resource.pinned },
                        set: { pinned in
                            if hapticsEnabled { pinHapticTrigger += 1 }
                            Task { await viewModel.setPinned(resource, pinned: pinned) }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(resource.title)
                            Text("\(resource.kind.rawValue.capitalized) · \(resource.state.rawValue.capitalized)")
                                .font(LVTypography.caption.font)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .disabled(!viewModel.canManage || !resource.curatorManaged || viewModel.isWorking)
                    .accessibilityHint("Pinned resources are never changed or archived by curator")
                }
            } header: {
                Text("Protected skills & jobs")
            } footer: {
                Text("Pinned resources are never consolidated, marked stale, or archived. Pinning a job also protects its backing skill.")
            }

            Section("Reports") {
                if viewModel.runs.isEmpty {
                    Text("No reviews yet.").foregroundStyle(palette.textSecondary)
                }
                ForEach(viewModel.runs) { run in
                    DisclosureGroup {
                        if let report = run.reportMarkdown {
                            Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                        if run.status == .succeeded, !run.dryRun, run.kind == .curator {
                            Button("Roll back this run", role: .destructive) {
                                Task { await viewModel.rollback(run) }
                            }
                            .disabled(!viewModel.canManage)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(run.kind == .curator ? "Curator" : "SOUL review")
                            Text("\(run.status.rawValue.capitalized) · \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(LVTypography.caption.font)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.backgroundBase)
        .navigationTitle("Self-Improvement")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await viewModel.save() } }
                    .disabled(viewModel.isWorking || !viewModel.canManage)
            }
        }
        .overlay { if viewModel.isLoading { ProgressView().tint(palette.primary) } }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert("Apply this SOUL.md patch?", isPresented: Binding(
            get: { approvalCandidate != nil },
            set: { if !$0 { approvalCandidate = nil } }
        )) {
            Button("Cancel", role: .cancel) { approvalCandidate = nil }
            Button("Apply") {
                guard let change = approvalCandidate else { return }
                approvalCandidate = nil
                if hapticsEnabled { approveHapticTrigger += 1 }
                Task { await viewModel.decide(change, approve: true) }
            }
        } message: {
            Text("The server verifies that SOUL.md has not changed since this proposal was created.")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pinHapticTrigger)
        .sensoryFeedback(.success, trigger: approveHapticTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: rejectHapticTrigger)
    }
}
