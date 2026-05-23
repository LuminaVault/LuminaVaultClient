// LuminaVaultClient/LuminaVaultClient/Features/Settings/PasskeysPaneView.swift
//
// HER-216 — Settings pane for managing enrolled WebAuthn passkeys.
//
// Three responsibilities:
//   1. List existing credentials (`GET /v1/auth/webauthn/credentials`).
//   2. "Add a passkey" cell — calls `vm.registerPasskey`.
//   3. Per-row revoke (`DELETE /v1/auth/webauthn/credentials/{id}`).
//
// Wiring into `SettingsRootView` is intentionally left as a follow-up
// so this scaffold stays scoped to HER-216 itself.

import SwiftUI

@MainActor
@Observable
final class PasskeysPaneViewModel {
    private let authClient: any AuthClientProtocol
    private let authViewModel: AuthViewModel

    var credentials: [WebAuthnCredentialSummaryDTO] = []
    var isLoading = false
    var error: String? = nil

    init(authClient: any AuthClientProtocol, authViewModel: AuthViewModel) {
        self.authClient = authClient
        self.authViewModel = authViewModel
    }

    func load() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            credentials = try await authClient.webAuthnListCredentials().credentials
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func revoke(_ credential: WebAuthnCredentialSummaryDTO) async {
        do {
            try await authClient.webAuthnDeleteCredential(credentialID: credential.id)
            credentials.removeAll { $0.id == credential.id }
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Enrol a passkey for the currently authenticated user, then refresh
    /// the list so the new credential shows up.
    func enrol(username: String) async {
        await authViewModel.registerPasskey(username: username, displayName: nil)
        await load()
    }
}

struct PasskeysPaneView: View {
    @Environment(\.lvPalette) private var palette
    @Bindable var vm: PasskeysPaneViewModel
    /// Username for the authenticated user — Settings provides this from
    /// `AppState.me?.username`. Empty string disables the enrol button.
    let username: String

    var body: some View {
        List {
            Section {
                Button {
                    Task { await vm.enrol(username: username) }
                } label: {
                    HStack {
                        Image(systemName: "key.fill")
                        Text("Add a passkey")
                    }
                }
                .disabled(username.isEmpty || vm.isLoading)
            }

            Section("Enrolled passkeys") {
                if vm.credentials.isEmpty, !vm.isLoading {
                    Text("No passkeys enrolled yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                }
                ForEach(vm.credentials) { credential in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(credential.nickname ?? "Passkey")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Added \(credential.createdAt.formatted(.dateTime.month().day().year()))")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        Button("Revoke", role: .destructive) {
                            Task { await vm.revoke(credential) }
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                }
            }

            if let error = vm.error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Passkeys")
        .task { await vm.load() }
    }
}
