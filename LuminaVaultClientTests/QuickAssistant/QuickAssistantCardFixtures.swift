// LuminaVaultClient/LuminaVaultClientTests/QuickAssistant/QuickAssistantCardFixtures.swift
//
// Stubs shared by the card's session and snapshot tests. The stream is scripted
// and never touches a network. With `holdsStream` it stays open, which is how a
// test keeps a turn in flight.
import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared

final class QuickAssistantStubConversations: ConversationsClientProtocol, @unchecked Sendable {
    // @unchecked: tests drive it from the main actor, and the stream's
    // termination handler only sets a flag read after a main-actor wait.
    var script: [QueryStreamEvent] = []
    var holdsStream = false
    private(set) var requests: [MessageStreamRequest] = []
    private(set) var streamTerminated = false

    func create(_: ConversationCreateRequest) async throws -> ConversationDTO {
        ConversationDTO(id: UUID(), title: "", createdAt: Date(), updatedAt: Date(), pinnedMemoryIDs: [])
    }

    func list() async throws -> ConversationListResponse { throw URLError(.unsupportedURL) }
    func get(_: UUID) async throws -> ConversationDetailResponse { throw URLError(.unsupportedURL) }
    func delete(_: UUID) async throws {}

    func streamReply(
        conversationID _: UUID,
        request: MessageStreamRequest
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        requests.append(request)
        let events = script
        let holds = holdsStream
        return AsyncThrowingStream { continuation in
            events.forEach { continuation.yield($0) }
            if holds {
                continuation.onTermination = { _ in self.streamTerminated = true }
            } else {
                continuation.finish()
            }
        }
    }
}

struct QuickAssistantStubActions: AssistantActionsClientProtocol {
    func confirm(_: UUID) async throws -> AssistantActionResolutionDTO { throw URLError(.unsupportedURL) }
    func cancel(_: UUID) async throws -> AssistantActionResolutionDTO { throw URLError(.unsupportedURL) }
}

@MainActor
enum QuickAssistantFixture {
    /// A settings store on a throwaway suite that allows cloud turns.
    static func settings() -> HybridExecutionSettingsStore {
        let store = HybridExecutionSettingsStore(
            defaults: UserDefaults(suiteName: "QuickAssistantFixture.\(UUID().uuidString)")!
        )
        store.profile = .quality
        store.cloudFallbackEnabled = true
        return store
    }

    static func session(
        conversations: QuickAssistantStubConversations = QuickAssistantStubConversations(),
        recognizer: StubSpeechRecognizer = StubSpeechRecognizer(available: true, authorized: true),
        synthesizer: StubSpeechSynthesizer = StubSpeechSynthesizer(),
        currentTab: String = "home",
        activeSpaceID: UUID? = nil
    ) -> QuickAssistantSession {
        QuickAssistantSession(
            model: QuickAssistantModel(
                conversations: conversations,
                actions: QuickAssistantStubActions(),
                settings: settings(),
                synthesizer: synthesizer,
                isOnline: { true }
            ),
            voice: VoiceModeController(recognizer: recognizer, synthesizer: synthesizer),
            synthesizer: synthesizer,
            context: { QuickAssistantSendContext(currentTab: currentTab, activeSpaceID: activeSpaceID) }
        )
    }
}
