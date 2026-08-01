// LuminaVaultClient/LuminaVaultClient/Services/Spotlight/SpotlightIndexer.swift
//
// Publishes memories to the system index so vault content is findable from
// iOS Search without opening the app.
//
// Cheapest of the three system-integration surfaces and the one that pays off
// first: no new target, no App Group, no entitlement — just an index write and
// a deep link back in.
//
// Privacy note: `CSSearchableIndex.default()` is the *private*, per-app,
// on-device index. Items are not published to Apple, not shared with other
// apps, and are removed when the app is deleted. Nothing here opts into
// public/web indexing (`isEligibleForPublicIndexing` stays unset).

import CoreSpotlight
import Foundation
import LuminaVaultShared
import OSLog
import UniformTypeIdentifiers

private let log = Logger(subsystem: "com.luminavault", category: "spotlight")

/// Domain used for bulk deletion on sign-out. All LuminaVault items share it,
/// so one call clears everything this app contributed.
enum SpotlightDomain {
    static let memories = "com.lumina.fernando.memories"
    /// `NSUserActivity` / `CSSearchableItem` identifiers are prefixed so the
    /// deep-link router can tell a Spotlight open from a push open.
    static let memoryIdentifierPrefix = "memory:"

    static func identifier(for memoryID: UUID) -> String {
        memoryIdentifierPrefix + memoryID.uuidString
    }

    /// Extracts a memory id from a Spotlight item identifier, or nil.
    static func memoryID(fromIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(memoryIdentifierPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(memoryIdentifierPrefix.count)))
    }
}

actor SpotlightIndexer {
    private let index: CSSearchableIndex

    init(index: CSSearchableIndex = .default()) {
        self.index = index
    }

    /// True when the device supports indexing. Guard every call — Spotlight is
    /// unavailable on some configurations and the API throws rather than no-ops.
    nonisolated var isAvailable: Bool {
        CSSearchableIndex.isIndexingAvailable()
    }

    /// Index a batch of memories. Best-effort: a failure here must never
    /// surface to the user or block a sync, so it logs and returns.
    func index(memories: [MemoryDTO]) async {
        guard isAvailable, !memories.isEmpty else { return }
        let items = memories.map(Self.searchableItem(for:))
        do {
            try await index.indexSearchableItems(items)
            log.info("indexed \(items.count) memories into Spotlight")
        } catch {
            log.error("Spotlight index failed: \(error.localizedDescription)")
        }
    }

    func remove(memoryIDs: [UUID]) async {
        guard isAvailable, !memoryIDs.isEmpty else { return }
        do {
            try await index.deleteSearchableItems(
                withIdentifiers: memoryIDs.map(SpotlightDomain.identifier(for:))
            )
        } catch {
            log.error("Spotlight delete failed: \(error.localizedDescription)")
        }
    }

    /// Clears everything this app contributed. MUST run on sign-out: the index
    /// outlives the session, and leaving one user's note titles searchable
    /// after they log out would leak them to the next person on the device.
    func removeAll() async {
        guard isAvailable else { return }
        do {
            try await index.deleteSearchableItems(withDomainIdentifiers: [SpotlightDomain.memories])
            log.info("cleared Spotlight index")
        } catch {
            log.error("Spotlight clear failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Mapping

    static func searchableItem(for memory: MemoryDTO) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title(for: memory)
        attributes.contentDescription = snippet(for: memory)
        attributes.keywords = memory.tags
        attributes.contentCreationDate = memory.createdAt
        if let placeName = memory.placeName, !placeName.isEmpty {
            attributes.namedLocation = placeName
        }
        if let lat = memory.lat, let lng = memory.lng {
            attributes.latitude = NSNumber(value: lat)
            attributes.longitude = NSNumber(value: lng)
        }

        let item = CSSearchableItem(
            uniqueIdentifier: SpotlightDomain.identifier(for: memory.id),
            domainIdentifier: SpotlightDomain.memories,
            attributeSet: attributes
        )
        // Memories are personal notes; expire them from the index after a year
        // of no refresh rather than letting stale copies linger forever.
        item.expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())
        return item
    }

    /// First non-empty line, bounded. Memory bodies can be long; a whole note
    /// makes an unreadable Spotlight row.
    static func title(for memory: MemoryDTO) -> String {
        let firstLine = memory.content
            .split(separator: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let firstLine, !firstLine.isEmpty else { return "Memory" }
        return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
    }

    static func snippet(for memory: MemoryDTO) -> String {
        let flattened = memory.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return flattened.count > 200 ? String(flattened.prefix(200)) + "…" : flattened
    }
}
