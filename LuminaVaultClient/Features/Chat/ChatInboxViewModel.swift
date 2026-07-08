// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatInboxViewModel.swift
import Foundation

@Observable
@MainActor
final class ChatInboxViewModel {
    var items: [ChatInboxItemDTO] = []
    var isLoading = false
    var errorMessage: String?

    private let client: any ChatExperienceClientProtocol
    private let conversationsClient: any ConversationsClientProtocol

    init(
        client: any ChatExperienceClientProtocol,
        conversationsClient: any ConversationsClientProtocol
    ) {
        self.client = client
        self.conversationsClient = conversationsClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            items = try await client.inbox(limit: 50).items
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(_ item: ChatInboxItemDTO) async {
        do {
            try await conversationsClient.delete(item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
