// LuminaVaultClient/LuminaVaultClient/Features/Settings/SystemManagement/HermesUpdateView.swift
//
// HER-330 — owner-facing "Update Hermes" screen. Shows the running version,
// confirms intent, streams step-by-step progress, and on failure offers a
// rollback. Updating a critical system, so copy is reassuring and explicit.

import LuminaVaultShared
import SwiftUI

struct HermesUpdateView: View {
    @State private var viewModel: HermesUpdateViewModel
    @State private var showConfirm = false

    init(client: SystemHermesHTTPClient) {
        _viewModel = State(initialValue: HermesUpdateViewModel(client: client))
    }

    var body: some View {
        Form {
            switch viewModel.phase {
            case .loadingVersion:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .idle:
                versionSection
                updateButtonSection
            case .updating, .rollingBack:
                progressSection(title: viewModel.phase == .rollingBack ? "Restoring previous version" : "Updating Hermes")
            case .succeeded:
                successSection
            case .rolledBack:
                rolledBackSection
            case .failed:
                failedSection
            case let .loadError(message):
                loadErrorSection(message)
            }
        }
        .navigationTitle("Update Hermes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onDisappear { viewModel.onDisappear() }
        .confirmationDialog(
            "Update Hermes?",
            isPresented: $showConfirm,
            titleVisibility: .visible,
        ) {
            Button("Update now") { Task { await viewModel.startUpdate() } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Your assistant will be briefly unavailable while the new version starts. Your memories and connected accounts are kept safe.")
        }
    }

    // MARK: - Idle / version

    @ViewBuilder
    private var versionSection: some View {
        if let info = viewModel.version {
            Section("Current version") {
                LabeledContent("Running", value: info.currentLabel)
                if let digest = info.currentDigest {
                    LabeledContent("Image") { Text(digest).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
                if let updated = info.lastUpdatedAt {
                    LabeledContent("Last updated", value: updated.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section {
                if info.updateAvailable, let available = info.availableLabel {
                    Label("A new version is available (\(info.currentLabel) → \(available)).", systemImage: "arrow.up.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("You're running the latest version.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var updateButtonSection: some View {
        Section {
            Button {
                showConfirm = true
            } label: {
                Label("Update Hermes", systemImage: "tray.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            Text("Downloads and installs the latest Hermes safely, with an automatic restore if anything goes wrong.")
        }
    }

    // MARK: - Progress

    private func progressSection(title: String) -> some View {
        Section(title) {
            ForEach(stepsForDisplay) { step in
                stepRow(step)
            }
        } footer: {
            Text("Keep this screen open, or come back later — the update continues on your server even if you leave.")
        }
    }

    /// The live steps, or a placeholder list before the first event arrives.
    private var stepsForDisplay: [HermesUpdateStep] {
        let steps = viewModel.job?.steps ?? []
        if !steps.isEmpty { return steps }
        return HermesUpdateStepID.pipelineForDisplay.map { HermesUpdateStep(id: $0, state: .pending) }
    }

    @ViewBuilder
    private func stepRow(_ step: HermesUpdateStep) -> some View {
        HStack(spacing: 12) {
            stepIcon(step.state)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.id.displayLabel)
                    .foregroundStyle(step.state == .pending ? .secondary : .primary)
                if let detail = step.detail, step.state == .failed {
                    Text(detail).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func stepIcon(_ state: HermesUpdateStepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(.tertiary)
        }
    }

    // MARK: - Terminal states

    private var successSection: some View {
        Section {
            Label("Hermes is now up to date.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
            if let to = viewModel.job?.toVersion {
                LabeledContent("Version", value: to)
            }
            Button("Done") { Task { await viewModel.reset() } }
        }
    }

    private var rolledBackSection: some View {
        Section {
            Label("Update didn't complete — previous version restored.", systemImage: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(.orange)
            Text(viewModel.job?.errorMessage ?? "Your assistant is back online on the previous version.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Try again") { Task { await viewModel.reset() } }
            Button("Dismiss", role: .cancel) { Task { await viewModel.reset() } }
        }
    }

    private var failedSection: some View {
        Section {
            Label("Update failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(viewModel.job?.errorMessage ?? "The update failed. You can restore the previous version.")
                .font(.callout).foregroundStyle(.secondary)
            if let failedStep = viewModel.job?.steps.first(where: { $0.state == .failed }) {
                LabeledContent("Failed at", value: failedStep.id.displayLabel)
            }
        }
        Section {
            Button(role: .destructive) {
                Task { await viewModel.rollback() }
            } label: {
                Label("Roll back to previous version", systemImage: "arrow.uturn.backward")
            }
            Button("Dismiss", role: .cancel) { Task { await viewModel.reset() } }
        }
    }

    // MARK: - Load / auth error

    @ViewBuilder
    private func loadErrorSection(_ message: String) -> some View {
        Section {
            Text(message).foregroundStyle(viewModel.needsAdminToken ? .secondary : .red)
        }
        adminTokenSection
    }

    @ViewBuilder
    private var adminTokenSection: some View {
        if viewModel.needsAdminToken {
            Section("Server admin token") {
                SecureField("X-Admin-Token", text: $viewModel.adminTokenDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save & retry") {
                    viewModel.saveAdminToken()
                    Task { await viewModel.load() }
                }
            } footer: {
                Text("This is the `admin.token` configured on your server. It's stored securely on this device.")
            }
        }
        Section {
            Button("Retry") { Task { await viewModel.load() } }
        }
    }
}

// MARK: - Display helpers

extension HermesUpdateStepID {
    /// Reassuring, plain-language label for each pipeline step.
    var displayLabel: String {
        switch self {
        case .preflight: "Checking your server"
        case .pullImage: "Downloading the new version"
        case .verifyImage: "Verifying the download"
        case .snapshotCurrent: "Saving a restore point"
        case .swapCentral: "Starting the new version"
        case .healthCheckCentral: "Making sure Hermes is healthy"
        case .reprovisionTenants: "Updating your assistant"
        case .verifyTenants: "Final checks"
        case .promote: "Finishing up"
        case .rollback: "Restoring the previous version"
        }
    }

    /// Steps shown as a placeholder before the first SSE event lands
    /// (the happy-path pipeline, minus the failure-only `rollback`).
    static var pipelineForDisplay: [HermesUpdateStepID] {
        [.preflight, .pullImage, .verifyImage, .snapshotCurrent, .swapCentral,
         .healthCheckCentral, .reprovisionTenants, .verifyTenants, .promote]
    }
}
