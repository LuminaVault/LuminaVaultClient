// LuminaVaultClient/LuminaVaultClient/Services/ChatHistoryStore.swift
//
// HER-107 — persists the last N chat turns per conversation so the
// Think tab restores its state across cold launches. Backed by a single
// JSON file under the App Group container (falls back to the app's
// Application Support directory when the App Group entitlement is
// missing on a dev build).
//
// Schema:
//   {
//     "conversations": [
//       {
//         "id": "<uuid>",
//         "transport": "memory_grounded" | "fresh",
//         "messages": [{ "id": "<uuid>", "role": "user|assistant|system",
//                        "content": "…", "sources": [QueryHitDTO] }],
//         "updatedAt": "<iso8601>"
//       }
//     ]
//   }
//
// FIFO-capped at `Self.maxTurns` per conversation; the file is rewritten
// whole on every save (small N keeps this cheap).
import Foundation
import OSLog

private nonisolated(unsafe) let log = Logger(subsystem: "com.luminavault", category: "chat-history")

actor ChatHistoryStore {
    static let maxTurns = 50
    static let fileName = "chatHistory.json"

    // `nonisolated`: SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor would make these
    // @MainActor, breaking the synthesized `Decodable` (which must be
    // nonisolated). They're plain value types, so opting out is safe.
    nonisolated struct Snapshot: Codable, Sendable, Equatable {
        let id: UUID
        let transport: ChatViewModel.Transport
        var messages: [ChatViewModel.Message]
        var updatedAt: Date
    }

    nonisolated private struct Container: Codable, Sendable {
        var conversations: [Snapshot]
    }

    private let baseURL: URL

    init(baseURL: URL? = nil) {
        if let baseURL {
            self.baseURL = baseURL
        } else if let appGroup = SharedAppGroup.containerURL {
            self.baseURL = appGroup
        } else {
            // Dev fallback when the App Group entitlement isn't wired
            // — keeps the cache file inside the app sandbox.
            let docs = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true,
            )) ?? FileManager.default.temporaryDirectory
            self.baseURL = docs
        }
    }

    private var fileURL: URL { baseURL.appendingPathComponent(Self.fileName) }

    /// Load the most-recently-updated snapshot. Returns `nil` when the
    /// store is empty or unreadable.
    func loadMostRecent() throws -> Snapshot? {
        let container = readContainer()
        return container.conversations.max(by: { $0.updatedAt < $1.updatedAt })
    }

    /// Load a specific conversation by id.
    func load(conversationID: UUID) throws -> Snapshot? {
        let container = readContainer()
        return container.conversations.first(where: { $0.id == conversationID })
    }

    /// Upsert a snapshot. Caps messages to `maxTurns` (FIFO — oldest
    /// dropped first). Replaces any existing entry for the same id.
    func save(_ snapshot: Snapshot) throws {
        var container = readContainer()
        var capped = snapshot
        if capped.messages.count > Self.maxTurns {
            capped.messages = Array(capped.messages.suffix(Self.maxTurns))
        }
        container.conversations.removeAll(where: { $0.id == snapshot.id })
        container.conversations.append(capped)
        try writeContainer(container)
    }

    /// Remove a single snapshot.
    func clear(conversationID: UUID) throws {
        var container = readContainer()
        container.conversations.removeAll(where: { $0.id == conversationID })
        try writeContainer(container)
    }

    /// Wipe every snapshot. Sign-out path uses this so the next signed-in
    /// account doesn't inherit the previous one's chat history.
    func clearAll() throws {
        try writeContainer(Container(conversations: []))
    }

    // MARK: - File IO

    private func readContainer() -> Container {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return Container(conversations: [])
        }
        do {
            return try Self.decoder.decode(Container.self, from: data)
        } catch {
            log.error("chat history decode failed: \(error.localizedDescription); resetting")
            return Container(conversations: [])
        }
    }

    private func writeContainer(_ container: Container) throws {
        let data = try Self.encoder.encode(container)
        // Chat history is user PII. Encrypt at rest via Data Protection so the file
        // is unreadable until first unlock after boot (survives backup extraction /
        // offline disk access). `.completeUntilFirstUserAuthentication` — not
        // `.complete` — so background writes/reads still work while the device is
        // locked (the app group is accessed by the share extension too).
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

