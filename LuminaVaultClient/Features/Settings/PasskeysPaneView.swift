// LuminaVaultClient/LuminaVaultClient/Features/Settings/PasskeysPaneView.swift
//
// HER-216 — Settings pane for managing enrolled WebAuthn passkeys.
//
// Three responsibilities:
//   1. List existing credentials (`GET /v1/auth/webauthn/credentials`).
//   2. "Add a passkey" cell — calls `AuthViewModel.registerPasskey`.
//   3. Per-row revoke (`DELETE /v1/auth/webauthn/credentials/{id}`).
//
import PostHog
import SwiftUI

@MainActor
@Observable
final class PasskeysPaneViewModel {
    private let authClient: any AuthClientProtocol
    private let authViewModel: AuthViewModel

    var credentials: [WebAuthnCredentialSummaryDTO] = []
    var isLoading = false
    var error: String? = nil
    private(set) var username: String = ""

    init(authClient: any AuthClientProtocol, authViewModel: AuthViewModel) {
        self.authClient = authClient
        self.authViewModel = authViewModel
    }

    func load() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            let me = try await authClient.getMe()
            username = me.username
            credentials = try await authClient.webAuthnListCredentials().credentials
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func revoke(_ credential: WebAuthnCredentialSummaryDTO) async {
        do {
            try await authClient.webAuthnDeleteCredential(credentialID: credential.id)
            credentials.removeAll { $0.id == credential.id }
            PostHogSDK.shared.capture("auth_passkey_revoked")
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Enrol a passkey for the currently authenticated user, then refresh
    /// the list so the new credential shows up.
    func enrol() async {
        guard !username.isEmpty else {
            error = "Username unavailable. Try again."
            return
        }
        await authViewModel.registerPasskey(username: username, displayName: nil)
        if let error = authViewModel.error {
            self.error = error
            return
        }
        await load()
    }
}

struct PasskeysPaneView: View {
    @Environment(\.lvPalette) private var palette
    @Bindable var vm: PasskeysPaneViewModel

    var body: some View {
        List {
            Section {
                Button {
                    Task { await vm.enrol() }
                } label: {
                    HStack {
                        LVIconView(.keyFill)
                        Text("Add a passkey")
                    }
                }
                .disabled(vm.username.isEmpty || vm.isLoading)
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
