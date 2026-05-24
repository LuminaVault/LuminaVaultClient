// LuminaVaultClient/LuminaVaultClient/Features/Settings/PrivacyDataView.swift
//
// HER-212 — Settings → Privacy & Data.

import SwiftUI

struct PrivacyDataView: View {
    @State private var viewModel: PrivacyDataViewModel
    @State private var securityViewModel: SecuritySettingsViewModel
    @State private var shareItem: ShareItem? = nil

    init(
        viewModel: PrivacyDataViewModel,
        securityViewModel: SecuritySettingsViewModel
    ) {
        _viewModel = State(initialValue: viewModel)
        _securityViewModel = State(initialValue: securityViewModel)
    }

    var body: some View {
        List {
            securitySection
            exportSection
            deleteSection
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem, onDismiss: viewModel.didDismissShareSheet) { item in
            ShareSheet(activityItems: [item.url])
        }
    }

    // MARK: - Sections

    private var securitySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { securityViewModel.isBiometricUnlockEnabled },
                set: { enabled in
                    Task {
                        await securityViewModel.setBiometricUnlockEnabled(enabled)
                    }
                }
            )) {
                Label("Face ID / Touch ID", systemImage: "lock.shield")
            }
            .disabled(!securityViewModel.isBiometricUnlockAvailable || securityViewModel.isUpdating)

            if securityViewModel.isUpdating {
                HStack {
                    ProgressView()
                    Text("Verifying…")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let message = securityViewModel.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Security")
        } footer: {
            if securityViewModel.isBiometricUnlockAvailable {
                Text("Require local biometric verification before opening a stored LuminaVault session on app launch.")
            } else {
                Text("Face ID or Touch ID is not available on this device.")
            }
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                Task { await runExport() }
            } label: {
                HStack {
                    Label("Export my data", systemImage: "square.and.arrow.up")
                    Spacer()
                    if case .exporting = viewModel.exportPhase {
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)

            if case .failed(let message) = viewModel.exportPhase {
                Text(message).foregroundStyle(.red).font(.footnote)
            }
        } header: {
            Text("Export")
        } footer: {
            if let last = viewModel.lastExportAt {
                Text("Last exported \(last.formatted(.relative(presentation: .named))).")
            } else {
                Text("Streams a tar.gz archive of your vault. Open in Obsidian on iPad after importing into Files.")
            }
        }
    }

    private var deleteSection: some View {
        Section {
            switch viewModel.deletePhase {
            case .idle, .failed:
                Button("Delete my account", role: .destructive) {
                    viewModel.beginDelete()
                }
            case .confirming:
                VStack(alignment: .leading, spacing: 12) {
                    Text("Type **\(viewModel.requiredConfirmationPhrase)** to confirm. This is irreversible — all vault files, memories, and account data will be permanently destroyed.")
                        .font(.footnote)
                    TextField(viewModel.requiredConfirmationPhrase, text: $viewModel.deletionConfirmInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    if !viewModel.hasDismissedExportSheet {
                        Text("Export your data first — the Delete button enables after you dismiss the share sheet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Cancel") { viewModel.cancelDelete() }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("Permanently delete", role: .destructive) {
                            Task { await viewModel.confirmDelete() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(!viewModel.canDelete)
                    }
                }
                .padding(.vertical, 4)
            case .deleting:
                HStack {
                    ProgressView()
                    Text("Deleting account…")
                }
            }

            if case .failed(let message) = viewModel.deletePhase {
                Text(message).foregroundStyle(.red).font(.footnote)
            }
        } header: {
            Text("Delete account")
        } footer: {
            Text("Removes your account and every byte of tenant data from LuminaVault servers. Cannot be undone.")
        }
    }

    // MARK: - Helpers

    private var isExporting: Bool {
        if case .exporting = viewModel.exportPhase { return true }
        return false
    }

    private func runExport() async {
        await viewModel.exportData()
        if case .ready(let url) = viewModel.exportPhase {
            shareItem = ShareItem(url: url)
        }
    }
}

// MARK: - Share sheet glue

private struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
