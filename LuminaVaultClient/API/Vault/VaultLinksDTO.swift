// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultLinksDTO.swift
// Backlog E2.2: GET /v1/vault/links/{vaultFileID}, a note's wikilinks both
// ways. Mirrors the Go `linksResponse` (internal/modules/vault/index.go) and
// `chunkindex.OutgoingLink` / `IncomingLink`. Keys are camelCase on the wire,
// which `JSONDecoder.hvDefault`'s convertFromSnakeCase leaves untouched.
import Foundation

nonisolated struct VaultLinksResponse: Decodable, Sendable, Equatable {
    let vaultFileID: UUID
    let path: String
    let outgoing: [VaultOutgoingLink]
    /// Backlinks: the notes whose wikilinks point at this one.
    let incoming: [VaultIncomingLink]
}

nonisolated struct VaultOutgoingLink: Decodable, Sendable, Equatable {
    let sourceLine: Int
    let rawTarget: String
    let targetSlug: String
    let resolutionState: String
    /// Set when the target note exists.
    let targetPath: String?

    init(sourceLine: Int = 1, rawTarget: String, targetSlug: String, resolutionState: String = "resolved", targetPath: String?) {
        self.sourceLine = sourceLine
        self.rawTarget = rawTarget
        self.targetSlug = targetSlug
        self.resolutionState = resolutionState
        self.targetPath = targetPath
    }
}

nonisolated struct VaultIncomingLink: Decodable, Sendable, Equatable {
    let sourcePath: String?
    let sourceLine: Int
    let rawTarget: String
    let targetSlug: String
    let resolutionState: String

    init(sourcePath: String?, sourceLine: Int = 1, rawTarget: String, targetSlug: String, resolutionState: String = "resolved") {
        self.sourcePath = sourcePath
        self.sourceLine = sourceLine
        self.rawTarget = rawTarget
        self.targetSlug = targetSlug
        self.resolutionState = resolutionState
    }
}

/// The reader's view of a note's links: one row per note, sorted by path.
nonisolated struct NoteLinkGroups: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        /// The vault path to open, or nil for a link to a note not written yet.
        let path: String?
        let label: String
        /// How many times the link appears.
        var count: Int
        var id: String { (path ?? "missing:") + label.lowercased() }
    }

    var linkedFrom: [Row]
    var linksTo: [Row]
    /// Wikilinks whose target note doesn't exist yet.
    var unresolved: [Row]

    var isEmpty: Bool { linkedFrom.isEmpty && linksTo.isEmpty && unresolved.isEmpty }

    /// Groups a links response. Self-links and incoming rows without a source
    /// path are dropped, since opening them would go nowhere.
    init(_ links: VaultLinksResponse) {
        let selfPath = links.path
        var from: [String: Row] = [:]
        var to: [String: Row] = [:]
        var missing: [String: Row] = [:]

        func tally(_ rows: inout [String: Row], key: String, path: String?, label: String) {
            if rows[key] != nil { rows[key]?.count += 1 } else { rows[key] = Row(path: path, label: label, count: 1) }
        }

        for link in links.incoming {
            guard let path = link.sourcePath, !path.isEmpty, path != selfPath else { continue }
            tally(&from, key: path, path: path, label: path)
        }
        for link in links.outgoing {
            if let path = link.targetPath, !path.isEmpty {
                if path != selfPath { tally(&to, key: path, path: path, label: path) }
            } else {
                let label = link.rawTarget.isEmpty ? link.targetSlug : link.rawTarget
                tally(&missing, key: label.lowercased(), path: nil, label: label)
            }
        }

        func sorted(_ rows: [String: Row]) -> [Row] {
            rows.values.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }
        linkedFrom = sorted(from)
        linksTo = sorted(to)
        unresolved = sorted(missing)
    }
}
