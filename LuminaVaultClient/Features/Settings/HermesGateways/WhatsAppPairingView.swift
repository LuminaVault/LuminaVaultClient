// LuminaVaultClient/LuminaVaultClient/Features/Settings/HermesGateways/WhatsAppPairingView.swift
//
// WhatsApp QR pairing screen. Presented by HermesGatewayDetailView when the
// catalog entry's `pairingKind == .whatsappQR`. Renders the streamed terminal
// QR block-art in a monospaced Text the user scans with their phone's
// *WhatsApp → Settings → Linked Devices → Link a Device*.

import LuminaVaultShared
import SwiftUI

struct WhatsAppPairingView: View {
    let entry: HermesGatewayCatalogEntry
    @State private var viewModel: WhatsAppPairingViewModel
    @State private var showUnlinkConfirm = false

    init(entry: HermesGatewayCatalogEntry, client: any HermesGatewaysClientProtocol) {
        self.entry = entry
        _viewModel = State(initialValue: WhatsAppPairingViewModel(
            client: client,
            isPaired: entry.status == .verified,
        ))
    }

    var body: some View {
        Form {
            Section {
                Text("Link WhatsApp to your assistant by scanning a QR code — the same way WhatsApp Web works. No phone number or API key needed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isPaired, case .linked = viewModel.phase {
                linkedSection
            } else if viewModel.isPaired, viewModel.phase == .idle {
                pairedRestingSection
            } else {
                pairingSection
            }
        }
        .navigationTitle("WhatsApp")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Auto-start a pairing session unless we're already linked.
            if !viewModel.isPaired { await viewModel.startPairing() }
        }
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - Pairing (QR + status)

    @ViewBuilder
    private var pairingSection: some View {
        switch viewModel.phase {
        case .idle, .starting:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Starting pairing…").foregroundStyle(.secondary)
                }
            }
        case let .awaitingScan(art, refreshing):
            Section {
                qrView(art)
                instructions
            } footer: {
                if refreshing {
                    Label("Code expired — generating a fresh one…", systemImage: "arrow.clockwise")
                }
            }
        case .linking:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Scanned! Linking your device…")
                }
            }
        case .linked:
            linkedSection
        case let .failed(message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Try again") { Task { await viewModel.startPairing() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func qrView(_ art: String) -> some View {
        // Render the terminal block-art verbatim. A small fixed monospaced font
        // with zero line spacing keeps the QR's aspect ratio scannable.
        Text(art)
            .font(.system(size: 7, weight: .regular, design: .monospaced))
            .lineSpacing(0)
            .fixedSize(horizontal: true, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .accessibilityLabel("WhatsApp pairing QR code")
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("On your phone:").font(.caption).foregroundStyle(.secondary)
            Text("WhatsApp → Settings → Linked Devices → Link a Device, then scan this code.")
                .font(.caption)
        }
    }

    // MARK: - Terminal states

    private var linkedSection: some View {
        Section {
            Label("WhatsApp linked. Your assistant can now send and receive messages here.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
            unlinkButton
        }
    }

    private var pairedRestingSection: some View {
        Section {
            Label("WhatsApp is linked.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Button("Re-pair (scan a new code)") { Task { await viewModel.startPairing() } }
            unlinkButton
        }
    }

    private var unlinkButton: some View {
        Button("Unlink WhatsApp", role: .destructive) { showUnlinkConfirm = true }
            .disabled(viewModel.isUnlinking)
            .confirmationDialog(
                "Unlink WhatsApp?",
                isPresented: $showUnlinkConfirm,
                titleVisibility: .visible,
            ) {
                Button("Unlink", role: .destructive) { Task { await viewModel.unlink() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your assistant stops receiving WhatsApp messages until you pair again. This restarts the gateway on your Hermes host.")
            }
    }
}
