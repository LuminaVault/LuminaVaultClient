#if canImport(FoundationModels)
    import Foundation
    import FoundationModels
    import LuminaVaultShared

    @available(iOS 26.0, *)
    struct AppleOnDeviceChatExecutor: LocalChatExecuting {
        let displayName = "Apple Intelligence"
        let modelID = "apple-system-language-model"

        func isAvailable() async -> Bool {
            if case .available = SystemLanguageModel.default.availability {
                true
            } else {
                false
            }
        }

        func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, any Error> {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let prompt = messages
                            .map { "\($0.role.uppercased()):\n\($0.content)" }
                            .joined(separator: "\n\n")
                        let response = try await LanguageModelSession().respond(to: prompt)
                        try Task.checkCancellation()
                        continuation.yield(response.content)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
#endif

func makeAppleOnDeviceChatExecutor() -> (any LocalChatExecuting)? {
    #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleOnDeviceChatExecutor()
        }
    #endif
    return nil
}
