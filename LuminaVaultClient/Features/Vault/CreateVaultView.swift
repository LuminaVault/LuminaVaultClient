// LuminaVaultClient/LuminaVaultClient/Features/Vault/CreateVaultView.swift
// HER-35: post-auth gate. User hits this immediately after a fresh signup
// (and only the first time). Tapping the CTA seeds the vault folder
// hierarchy + default Spaces server-side, then unlocks MainTabView.
import SwiftUI

struct CreateVaultView: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: CreateVaultViewModel

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer(minLength: 24)

                HermieMascotView(state: vm.isLoading ? .thinking : .happy)
                    .frame(width: 200, height: 200)

                VStack(spacing: 12) {
                    Text("Welcome to LuminaVault.")
                        .font(.system(size: 28, weight: .heavy))
                        .multilineTextAlignment(.center)
                    Text("Let's build your second brain.")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Your private vault lives on your VPS. Everything stays under your control.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                if let error = vm.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                LVButton("Create My Vault", isLoading: vm.isLoading) {
                    Task { await vm.createVault() }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .disabled(vm.isLoading)
            }
            .padding(.top, 32)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [palette.secondary.opacity(0.15), palette.primary.opacity(0.05), Color.clear],
            startPoint: .top,
            endPoint: .bottom,
        )
    }
}

#Preview {
    CreateVaultView(
        vm: CreateVaultViewModel(
            vaultClient: PreviewVaultClient(),
            appState: AppState(),
        ),
    )
}

private final class PreviewVaultClient: VaultClientProtocol {
    func createVault() async throws -> VaultStatusResponse {
        VaultStatusResponse(initialized: true, createdAt: Date(), defaultSpaceSlugs: ["ai", "stocks"])
    }

    func status() async throws -> VaultStatusResponse {
        VaultStatusResponse(initialized: false)
    }

    func listFiles(
        spaceSlug _: String?,
        q _: String?,
        before _: Date?,
        after _: Date?,
        limit _: Int?,
    ) async throws -> VaultFileListResponse {
        VaultFileListResponse(files: [], limit: 0, nextBefore: nil)
    }

    func readFile(relativePath _: String) async throws -> (Data, String) {
        (Data(), "text/plain")
    }

    func moveFile(from _: String, to: String) async throws -> VaultFileDTO {
        VaultFileDTO(id: UUID(), path: to, contentType: "text/markdown", sizeBytes: 0, sha256: "")
    }

    func deleteFile(relativePath _: String) async throws {}

    func exportVault() async throws -> (Data, String) {
        (Data(), "application/gzip")
    }
}
