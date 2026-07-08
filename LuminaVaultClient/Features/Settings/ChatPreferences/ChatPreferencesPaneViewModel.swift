// LuminaVaultClient/LuminaVaultClient/Features/Settings/ChatPreferences/ChatPreferencesPaneViewModel.swift
import Foundation

@Observable
@MainActor
final class ChatPreferencesPaneViewModel {
    var preferences = ChatPreferencesDTO()
    var isLoading = false
    var isSaving = false
    var errorMessage: String?

    private let client: any ChatExperienceClientProtocol

    init(client: any ChatExperienceClientProtocol) {
        self.client = client
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            preferences = try await client.getPreferences().preferences
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setAutoExpandThinking(_ value: Bool) async {
        await save(ChatPreferencesDTO(
            autoExpandThinking: value,
            sendOnReturn: preferences.sendOnReturn
        ))
    }

    func setSendOnReturn(_ value: Bool) async {
        await save(ChatPreferencesDTO(
            autoExpandThinking: preferences.autoExpandThinking,
            sendOnReturn: value
        ))
    }

    private func save(_ next: ChatPreferencesDTO) async {
        preferences = next
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            preferences = try await client.putPreferences(next).preferences
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
