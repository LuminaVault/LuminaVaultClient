// LuminaVaultClient/LuminaVaultClient/Features/Settings/HermesGateways/PhotonSetupView.swift
//
// Dedicated setup flow for Photon iMessage (pairingKind == .photonSetup).
// Shows the device approval step (verification link + code), collects the
// user's iMessage-capable phone number, drives the SSE progress, and on
// success surfaces the stable assigned line that contacts text.

import LuminaVaultShared
import SwiftUI

struct PhotonSetupView: View {
    let entry: HermesGatewayCatalogEntry
    @State private var viewModel: PhotonSetupViewModel
    @State private var showDisconnectConfirm = false

    init(entry: HermesGatewayCatalogEntry, client: any HermesGatewaysClientProtocol) {
        self.entry = entry
        _viewModel = State(initialValue: PhotonSetupViewModel(
            client: client,
            isPaired: entry.status == .verified
        ))
    }

    var body: some View {
        Form {
            Section {
                Text("Text your Lumina assistant directly on iMessage for free via Photon shared lines. Approve in your browser, enter your phone number, and get a stable line to share.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isPaired, case .done = viewModel.phase {
                doneSection
            } else if viewModel.isPaired {
                pairedRestingSection
            } else {
                setupSection
            }
        }
        .navigationTitle("iMessage (Photon)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !viewModel.isPaired { await viewModel.startSetup() }
        }
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - Setup states

    @ViewBuilder
    private var setupSection: some View {
        switch viewModel.phase {
        case .idle, .starting:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Starting Photon setup…")
                        .foregroundStyle(.secondary)
                }
            }

        case let .awaitingApproval(verificationUri, userCode, expiresIn):
            Section("Approve in your browser") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Open this link (or enter the code on photon.codes):")
                        .font(.callout)

                    Link(verificationUri, destination: URL(string: verificationUri)!)
                        .font(.body)
                        .foregroundStyle(.blue)

                    HStack {
                        Text("Code:")
                            .foregroundStyle(.secondary)
                        Text(userCode)
                            .font(.system(.title3, design: .monospaced).bold())
                            .textSelection(.enabled)
                    }

                    Text("Expires in \(expiresIn / 60) minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("After you approve, come back here and enter the E.164 phone number you want to bind (e.g. +15551234567).")
            }

            Section("Your phone number") {
                TextField("+15551234567", text: $viewModel.phoneInput)
                    .keyboardType(.phonePad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Submit phone & continue") {
                    Task { await viewModel.submitPhone() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmittingPhone)
            }

        case .awaitingPhone:
            Section("Your phone number") {
                TextField("+15551234567", text: $viewModel.phoneInput)
                    .keyboardType(.phonePad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Submit phone & continue") {
                    Task { await viewModel.submitPhone() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmittingPhone)
            }

        case .provisioning:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Provisioning your iMessage line…")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("This can take a moment while we create the project, enable Spectrum, and register your number.")
            }

        case let .done(assignedLine):
            doneSection(assignedLine: assignedLine)

            // Allow disconnect even right after successful setup (mirrors WhatsApp paired state affordance).
            Section {
                Button("Disconnect", role: .destructive) { showDisconnectConfirm = true }
                    .disabled(viewModel.isPaired == false)
            }
            .confirmationDialog(
                "Remove Photon / iMessage config?",
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task {
                        await viewModel.disconnect()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the stored credentials. Your iMessage line will stop receiving messages from contacts until you set it up again.")
            }

        case let .failed(message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Try again") { Task { await viewModel.startSetup() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var pairedRestingSection: some View {
        Section {
            Label("Connected via Photon. Your assistant is reachable on iMessage.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        }

        Section {
            Button("Disconnect", role: .destructive) {
                showDisconnectConfirm = true
            }
        }
        .confirmationDialog(
            "Remove Photon config?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    await viewModel.disconnect()
                    // The parent detail view will handle the actual gateway delete call.
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the stored credentials. Your iMessage line will stop working until you set it up again.")
        }
    }

    @ViewBuilder
    private func doneSection(assignedLine: String? = nil) -> some View {
        let line = assignedLine ?? (if case .done(let l) = viewModel.phase { l } else { "" })

        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Success!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)

                Text("Your agent's iMessage number:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(line)
                    .font(.title3.bold())
                    .textSelection(.enabled)
                    .padding(.vertical, 4)

                Text("Text this number from iMessage to talk to your Lumina assistant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            Button("Done") {
                // The sheet / navigation will dismiss naturally; parent can refresh.
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
