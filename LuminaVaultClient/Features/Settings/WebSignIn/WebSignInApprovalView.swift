// LuminaVaultClient/LuminaVaultClient/Features/Settings/WebSignIn/WebSignInApprovalView.swift
//
// HER — "Approve Web Sign-In". Scan the QR shown on the LuminaVault website,
// confirm the code matches, and approve the browser session. The web client
// then receives a freshly minted token pair from the server.
import SwiftUI

/// A pairing carried in by a universal link, ready to present.
struct PendingPairingApproval: Identifiable, Equatable, Sendable {
    /// `Identifiable` for `.sheet(item:)`; the pairing id doubles as the id.
    let id: String
    /// `nil` for a universal link, which deliberately does not carry it — the
    /// browser shows it and the app asks. Non-nil only for the legacy scheme.
    let code: String?
}

@MainActor
@Observable
final class WebSignInApprovalViewModel {
    enum Phase: Equatable {
        case scanning
        /// Scanned a link that carries no code — the browser is showing it, and
        /// the point is that approving requires having seen that screen.
        case enterCode(pairingId: String)
        /// Legacy payload: the code travelled inside the QR, so there is
        /// nothing to ask for. Retires with the custom scheme.
        case confirm(pairingId: String, code: String)
        case approving
        case approved
        case failed(String)
    }

    private(set) var phase: Phase

    private let client: BaseHTTPClient

    /// `prefilled` skips the scanner: a universal link opened from the camera
    /// already carries the pairing, so re-scanning the code you just scanned
    /// would be absurd. The confirm step still stands — the whole point is that
    /// you check the code against the one on screen before approving.
    init(client: BaseHTTPClient, prefilled: (id: String, code: String?)? = nil) {
        self.client = client
        phase = Self.initialPhase(prefilled: prefilled)
    }

    /// Where a freshly opened approval starts.
    ///
    /// Split out so it can be tested without standing up an HTTP client: the
    /// decision it makes is the security-relevant one. A universal link carries
    /// no code, so it must land on `.enterCode` and force the person to read the
    /// six digits off the browser that started the sign-in; only the legacy
    /// scheme, whose builds cannot prompt, skips to `.confirm`.
    static func initialPhase(prefilled: (id: String, code: String?)?) -> Phase {
        guard let prefilled else { return .scanning }
        guard let code = prefilled.code, !code.isEmpty else {
            return .enterCode(pairingId: prefilled.id)
        }
        return .confirm(pairingId: prefilled.id, code: code)
    }

    func handleScan(_ raw: String) {
        guard case .scanning = phase else { return }
        guard let parsed = Self.parse(raw) else {
            phase = .failed("That QR code isn't a LuminaVault web sign-in.")
            return
        }
        if let code = parsed.code {
            phase = .confirm(pairingId: parsed.id, code: code)
        } else {
            phase = .enterCode(pairingId: parsed.id)
        }
    }

    func handleScanError(_ message: String) {
        phase = .failed(message)
    }

    /// `typedCode` is what the person read off the browser. It is the only
    /// thing tying this approval to that screen, so an empty one is refused
    /// here rather than sent for the server to reject.
    func approve(typedCode: String? = nil) async {
        let pairingId: String
        let code: String
        switch phase {
        case let .confirm(id, scannedCode):
            pairingId = id
            code = scannedCode
        case let .enterCode(id):
            let entered = (typedCode ?? "").trimmingCharacters(in: .whitespaces)
            guard !entered.isEmpty else { return }
            pairingId = id
            code = entered
        default:
            return
        }
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

    /// Hosts whose `/pair` links may drive an approval. A QR is attacker-supplied
    /// input — anyone can print one — so only the app's own web origins count.
    private static let pairingHosts: Set<String> = [
        "app.luminavault.fyi",
        "app-staging.luminavault.fyi"
    ]

    /// Parse a scanned or opened pairing link.
    ///
    /// Two forms are accepted. `https://app.luminavault.fyi/pair?id=&code=` is
    /// what the web app encodes now: a universal link, so the iPhone camera can
    /// open it and land here directly. `luminavault://pair?id=&code=` is the
    /// original payload — no installed app claims that scheme, which is why the
    /// camera used to answer "No usable data found" — and it stays supported
    /// because a code generated before the web switch flips must still scan.
    static func parse(_ raw: String) -> (id: String, code: String?)? {
        guard let components = URLComponents(string: raw) else { return nil }

        switch components.scheme {
        case "luminavault":
            guard components.host == "pair" else { return nil }
        case "https":
            guard let host = components.host,
                  pairingHosts.contains(host.lowercased()),
                  components.path == "/pair"
            else { return nil }
        default:
            // Notably `http`: a downgraded link is not one of ours.
            return nil
        }

        let items = components.queryItems ?? []
        guard let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty else {
            return nil
        }
        // Absent by design on a universal link: a QR that carries its own
        // confirmation confirms nothing, since anyone can print one. Present on
        // the legacy scheme, whose builds cannot prompt for it.
        let code = items.first(where: { $0.name == "code" })?.value
        guard let code, !code.isEmpty else { return (id, nil) }
        return (id, code)
    }
}

struct WebSignInApprovalView: View {
    @State private var viewModel: WebSignInApprovalViewModel
    /// The six digits read off the browser. Never prefilled — being handed this
    /// is exactly what makes a scanned code worthless as proof.
    @State private var typedCode = ""
    @FocusState private var codeFieldFocused: Bool

    init(client: BaseHTTPClient, prefilled: (id: String, code: String?)? = nil) {
        _viewModel = State(
            initialValue: WebSignInApprovalViewModel(client: client, prefilled: prefilled)
        )
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

            case .enterCode:
                Text("Approve web sign-in?")
                    .font(.title2.bold())
                Text("Type the six digits shown next to the QR code in your browser.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                TextField("000000", text: $typedCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.system(.title, design: .monospaced).bold())
                    .tracking(8)
                    .focused($codeFieldFocused)
                    .onAppear { codeFieldFocused = true }
                    .onChange(of: typedCode) { _, new in
                        // Digits only, six of them: the field should not let you
                        // paste something that can only fail server-side.
                        let digits = new.filter(\.isNumber)
                        if digits != new || digits.count > 6 {
                            typedCode = String(digits.prefix(6))
                        }
                    }
                Text("If you did not start a sign-in, do not approve this.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                VStack(spacing: LVSpacing.sm) {
                    Button {
                        Task { await viewModel.approve(typedCode: typedCode) }
                    } label: {
                        Text("Approve").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(typedCode.count != 6)
                    Button("Cancel") {
                        typedCode = ""
                        viewModel.reset()
                    }
                    .buttonStyle(.bordered)
                }

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
