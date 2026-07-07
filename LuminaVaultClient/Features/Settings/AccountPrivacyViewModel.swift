// LuminaVaultClient/LuminaVaultClient/Features/Settings/AccountPrivacyViewModel.swift
import Foundation

@Observable
@MainActor
final class AccountPrivacyViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private let authClient: any AuthClientProtocol

    private(set) var state: LoadState = .loading
    private(set) var isSaving = false
    private(set) var profile: MeResponse?

    init(authClient: any AuthClientProtocol) {
        self.authClient = authClient
    }

    var email: String { profile?.email ?? "" }
    var username: String { profile?.username ?? "" }
    var privacyNoCNOrigin: Bool { profile?.privacyNoCNOrigin ?? false }
    var contextRouting: Bool { profile?.contextRouting ?? true }
    var autoSaveLinks: Bool { profile?.autoSaveLinks ?? true }
    var mnemosyneEnabled: Bool { profile?.mnemosyneEnabled ?? true }

    func load() async {
        state = .loading
        do {
            profile = try await authClient.getMe()
            state = .loaded
        } catch {
            state = .failed(Self.loadMessage(for: error))
        }
    }

    func setPrivacyNoCNOrigin(_ enabled: Bool) async {
        await update(UpdatePrivacyRequest(
            privacyNoCNOrigin: enabled,
            contextRouting: nil
        ))
    }

    func setContextRouting(_ enabled: Bool) async {
        await update(UpdatePrivacyRequest(
            privacyNoCNOrigin: nil,
            contextRouting: enabled
        ))
    }

    func setAutoSaveLinks(_ enabled: Bool) async {
        await update(UpdatePrivacyRequest(
            privacyNoCNOrigin: nil,
            contextRouting: nil,
            autoSaveLinks: enabled
        ))
    }

    func setMnemosyneEnabled(_ enabled: Bool) async {
        await update(UpdatePrivacyRequest(
            privacyNoCNOrigin: nil,
            contextRouting: nil,
            mnemosyneEnabled: enabled
        ))
    }

    private func update(_ request: UpdatePrivacyRequest) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await authClient.updatePrivacy(request)
            state = .loaded
        } catch {
            state = .failed(Self.updateMessage(for: error))
        }
    }

    private static func loadMessage(for error: Error) -> String {
        switch error {
        case APIError.unauthorized:
            return "Session expired — sign in again."
        case APIError.networkFailure(_):
            return "Network unavailable."
        default:
            return "Couldn't load account privacy settings."
        }
    }

    private static func updateMessage(for error: Error) -> String {
        switch error {
        case APIError.unauthorized:
            return "Session expired — sign in again."
        case APIError.networkFailure(_):
            return "Network unavailable."
        default:
            return "Couldn't update account privacy settings."
        }
    }
}
