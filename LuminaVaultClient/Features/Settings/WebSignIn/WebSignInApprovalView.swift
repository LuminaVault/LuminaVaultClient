// LuminaVaultClient/LuminaVaultClient/Features/Settings/WebSignIn/WebSignInApprovalView.swift
//
// HER — "Approve Web Sign-In". Scan the QR shown on the LuminaVault website,
// confirm the code matches, and approve the browser session. The web client
// then receives a freshly minted token pair from the server.
import SwiftUI

@MainActor
@Observable
final class WebSignInApprovalViewModel {
    enum Phase: Equatable {
        case scanning
        case confirm(pairingId: String, code: String)
        case approving
        case approved
        case failed(String)
    }

    private(set) var phase: Phase = .scanning

    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func handleScan(_ raw: String) {
        guard case .scanning = phase else { return }
        guard let parsed = Self.parse(raw) else {
            phase = .failed("That QR code isn't a LuminaVault web sign-in.")
            return
        }
        phase = .confirm(pairingId: parsed.id, code: parsed.code)
    }

    func handleScanError(_ message: String) {
        phase = .failed(message)
    }

    func approve() async {
        guard case let .confirm(pairingId, code) = phase else { return }
        phase = .approving
        do {
            _ = try await client.execute(PairingEndpoints.Approve(pairingId: pairingId, code: code))
            phase = .approved
        } catch {
            phase = .failed("Could not approve this sign-in. Request a fresh code on the web and try again.")
        }
    }

    func reset() {
        phase = .scanning
    }

    /// Parse `luminavault://pair?id=<pairingId>&code=<code>`.
    static func parse(_ raw: String) -> (id: String, code: String)? {
        guard
            let components = URLComponents(string: raw),
            components.scheme == "luminavault",
            components.host == "pair"
        else { return nil }
        let items = components.queryItems ?? []
        guard
            let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty,
            let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty
        else { return nil }
        return (id, code)
    }
}

struct WebSignInApprovalView: View {
    @State private var viewModel: WebSignInApprovalViewModel

    init(client: BaseHTTPClient) {
        _viewModel = State(initialValue: WebSignInApprovalViewModel(client: client))
    }

    var body: some View {
        VStack(spacing: LVSpacing.lg) {
            switch viewModel.phase {
            case .scanning:
                Text("Scan the QR code on the LuminaVault website to sign that browser in.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                QRScannerView(
                    onScan: { viewModel.handleScan($0) },
                    onError: { viewModel.handleScanError($0) }
                )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous))

            case let .confirm(_, code):
                Text("Approve web sign-in?")
                    .font(.title2.bold())
                Text("Confirm this code matches the one shown in your browser.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text(code)
                    .font(.system(.title, design: .monospaced).bold())
                    .tracking(4)
                VStack(spacing: LVSpacing.sm) {
                    Button {
                        Task { await viewModel.approve() }
                    } label: {
                        Text("Approve").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel") { viewModel.reset() }
                        .buttonStyle(.bordered)
                }

            case .approving:
                ProgressView("Approving…")

            case .approved:
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Browser signed in.")
                    .font(.headline)
                Text("You can close this and return to the web dashboard.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

            case let .failed(message):
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try again") { viewModel.reset() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(LVSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Approve Web Sign-In")
        .navigationBarTitleDisplayMode(.inline)
    }
}
