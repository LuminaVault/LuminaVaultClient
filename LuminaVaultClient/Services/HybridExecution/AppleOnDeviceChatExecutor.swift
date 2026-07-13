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
                        let snapshots = LanguageModelSession().streamResponse(to: prompt)
                        var previous = ""
                        for try await snapshot in snapshots {
                            try Task.checkCancellation()
                            let content = snapshot.content
                            let delta = content.hasPrefix(previous)
                                ? String(content.dropFirst(previous.count))
                                : content
                            if !delta.isEmpty {
                                continuation.yield(delta)
                            }
                            previous = content
                        }
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
            if case .available = SystemLanguageModel.default.availability {
                return AppleOnDeviceChatExecutor()
            }
        }
    #endif
    return nil
}
